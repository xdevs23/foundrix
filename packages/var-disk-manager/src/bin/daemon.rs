//! var-disk-managerd — initrd daemon that classifies the glob-selected
//! data volumes and unlocks, migrates, blocks or provisions accordingly.
//!
//! Runs as a oneshot systemd unit: exiting 0 releases the boot
//! (sysroot-var.mount Requires/After this unit), exiting non-zero fails
//! to the emergency target, and the deliberate block states simply never
//! exit. UI state is served to TUI clients over a unix socket; disk work
//! is delegated to the battle-tested C tools present in the initrd's /bin.

use std::path::Path;
use std::process::Stdio;
use std::sync::Mutex;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use clap::Parser;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::process::Command;
use tokio::sync::{mpsc, watch};

use var_disk_manager::{
    ClientMsg, DiskClass, DiskInfo, DiskProbe, Identity, MapperFs, Plan, Progress, Prompt,
    PromptKind, SOCKET_PATH, STATE_FILE, Snapshot, VAR_TYPE_GUID, classify, mapper_fs_from_blkid,
    parse_btrfs_used, parse_confirm, plan, split_prefix_glob,
};

#[derive(Parser)]
#[command(about = "Initrd daemon managing the encrypted /var data volume")]
struct Cli {
    /// Volume glob of the form <dir>/<prefix>* selecting the data disks
    /// (whole-disk by-id links; partitions are skipped automatically).
    #[arg(long)]
    volume_glob: String,

    /// PARTUUID assigned to (and required of) the LUKS partition.
    #[arg(long)]
    luks_partuuid: String,

    /// btrfs filesystem label /var is mounted by.
    #[arg(long, default_value = "var")]
    fs_label: String,

    /// dm mapper name for the opened LUKS volume.
    #[arg(long, default_value = "var")]
    mapper: String,

    /// Minimum passphrase length enforced at creation.
    #[arg(long, default_value_t = 12)]
    min_passphrase_len: usize,
}

/// Runtime configuration resolved from the CLI.
struct Cfg {
    by_id_dir: String,
    prefix: String,
    id: Identity,
    min_passphrase_len: usize,
}
const REQUIRED_TOOLS: &[&str] = &[
    "blkid",
    "lsblk",
    "blockdev",
    "wipefs",
    "sgdisk",
    "cryptsetup",
    "btrfs",
    "mkfs.btrfs",
    "udevadm",
    "mount",
    "umount",
    "sync",
];
/// LUKS header + btrfs metadata headroom the target must have beyond the
/// source's used bytes.
const SIZE_HEADROOM: u64 = 1 << 30;

/// Slack a full-size partition may leave unused before growth is worth
/// doing: GPT metadata at both ends plus alignment never add up to this.
const GROW_THRESHOLD: u64 = 16 << 20;

/// Headroom between the partition and the mapper inside it that is
/// explained by the LUKS2 header alone. A larger gap means the mapping
/// was not resized after the partition grew.
const LUKS_HEADER_SLACK: u64 = 64 << 20;

// --- UI hub -----------------------------------------------------------------

struct Ui {
    snapshot: Mutex<Snapshot>,
    tx: watch::Sender<Snapshot>,
    submissions: Mutex<mpsc::UnboundedReceiver<ClientMsg>>,
    next_prompt_id: Mutex<u64>,
}

impl Ui {
    fn mutate(&self, f: impl FnOnce(&mut Snapshot)) {
        let mut snap = self.snapshot.lock().unwrap();
        f(&mut snap);
        // The state file and kmsg mirror the message line for `ssh host
        // 'cat ...'` scripting and crash forensics. <7> = KERN_DEBUG:
        // visible in dmesg/journal but below the console loglevel, so the
        // breadcrumbs don't garble our own console TUI.
        let _ = std::fs::write(STATE_FILE, format!("{}\n", snap.message));
        let _ = std::fs::write(
            "/dev/kmsg",
            format!("<7>var-disk-manager: {}\n", snap.message),
        );
        let _ = self.tx.send(snap.clone());
    }

    fn state(&self, phase: &str, message: impl Into<String>) {
        let message = message.into();
        eprintln!("var-disk-manager: {message}");
        self.mutate(|s| {
            s.phase = phase.into();
            s.message = message;
        });
    }

    fn progress(&self, copied: u64, total: u64) {
        self.mutate(|s| s.progress = Some(Progress { copied, total }));
    }

    /// Post a prompt and wait for the first answer from any client.
    async fn ask(&self, kind: PromptKind, text: &str) -> String {
        let id = {
            let mut n = self.next_prompt_id.lock().unwrap();
            *n += 1;
            *n
        };
        self.mutate(|s| {
            s.prompt = Some(Prompt {
                id,
                kind,
                text: text.to_string(),
            })
        });
        let value = loop {
            let msg = {
                let mut rx = self.submissions.lock().unwrap();
                match rx.try_recv() {
                    Ok(m) => Some(m),
                    Err(mpsc::error::TryRecvError::Empty) => None,
                    Err(mpsc::error::TryRecvError::Disconnected) => None,
                }
            };
            match msg {
                Some(ClientMsg::Submit { prompt_id, value }) if prompt_id == id => break value,
                Some(_) => continue, // stale answer to an older prompt
                None => tokio::time::sleep(Duration::from_millis(100)).await,
            }
        };
        self.mutate(|s| s.prompt = None);
        value
    }

    /// Post a yes/no Confirm prompt until a parseable answer arrives.
    /// This is a SAFETY INTERLOCK for irreversible decisions (currently:
    /// formatting an unlocked-but-empty mapper), not a convenience — there
    /// is deliberately no default, no config flag and no heuristic that can
    /// bypass the human answer.
    async fn ask_confirm(&self, text: &str) -> bool {
        loop {
            let answer = self.ask(PromptKind::Confirm, text).await;
            if let Some(yes) = parse_confirm(&answer) {
                return yes;
            }
            self.state("prompt", "please answer y or n");
        }
    }

    async fn block_forever(&self, reason: &str) -> std::convert::Infallible {
        self.state("blocked", format!("BLOCKED: {reason}"));
        self.mutate(|s| {
            s.blocked = true;
            s.progress = None;
        });
        loop {
            tokio::time::sleep(Duration::from_secs(60)).await;
            // Keepalive: re-broadcast so late-connecting or reconnecting
            // clients aren't parked on a watch channel that never fires,
            // and the kmsg breadcrumb keeps recurring like the shell
            // version's re-posted prompt did.
            self.mutate(|_| {});
        }
    }
}

// --- subprocess helpers -----------------------------------------------------

async fn run_ok(cmd: &str, args: &[&str]) -> Result<String> {
    let out = Command::new(cmd)
        .args(args)
        .output()
        .await
        .with_context(|| format!("spawning {cmd}"))?;
    if !out.status.success() {
        bail!(
            "{cmd} {} failed ({}): {}",
            args.join(" "),
            out.status,
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// Run a probe that legitimately exits non-zero when nothing is found.
async fn probe_value(cmd: &str, args: &[&str]) -> Result<Option<String>> {
    let out = Command::new(cmd)
        .args(args)
        .output()
        .await
        .with_context(|| format!("spawning {cmd}"))?;
    let v = String::from_utf8_lossy(&out.stdout).trim().to_string();
    Ok(if out.status.success() && !v.is_empty() {
        Some(v)
    } else {
        None
    })
}

/// Run a command feeding `secret` on stdin (cryptsetup --key-file=-).
async fn run_with_stdin(cmd: &str, args: &[&str], secret: &str) -> Result<()> {
    let mut child = Command::new(cmd)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("spawning {cmd}"))?;
    // A child that exits before reading stdin (e.g. cryptsetup rejecting
    // its arguments) EPIPEs this write; its own stderr is the diagnostic
    // that matters, so always collect the output before reporting.
    let write_result = child
        .stdin
        .take()
        .context("no stdin pipe")?
        .write_all(secret.as_bytes())
        .await; // stdin drops here -> EOF
    let out = child.wait_with_output().await?;
    if !out.status.success() {
        bail!(
            "{cmd} {} failed ({}): {}",
            args.join(" "),
            out.status,
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    write_result.with_context(|| format!("writing key material to {cmd} stdin"))?;
    Ok(())
}

async fn settle() {
    let _ = Command::new("udevadm")
        .args(["settle", "--timeout=30"])
        .status()
        .await;
}

// --- disk enumeration & probing ---------------------------------------------

fn list_volumes(cfg: &Cfg) -> Vec<String> {
    let mut v: Vec<String> = std::fs::read_dir(&cfg.by_id_dir)
        .map(|rd| {
            rd.filter_map(|e| e.ok())
                .filter_map(|e| e.file_name().into_string().ok())
                .filter(|n| n.starts_with(&cfg.prefix) && !n.contains("-part"))
                .collect()
        })
        .unwrap_or_default();
    v.sort();
    v
}

fn dev(cfg: &Cfg, id: &str) -> String {
    format!("{}/{id}", cfg.by_id_dir)
}

fn part1(cfg: &Cfg, id: &str) -> String {
    format!("{}/{id}-part1", cfg.by_id_dir)
}

async fn blockdev_bytes(path: &str) -> Result<u64> {
    let out = run_ok("blockdev", &["--getsize64", path]).await?;
    Ok(out.trim().parse()?)
}

/// Grow partition 1 to fill a backing volume that was enlarged. Runs
/// before the mapper is opened, because partition geometry needs no key
/// material. Returns whether the partition grew, so the caller knows to
/// extend the LUKS mapping once it holds the passphrase.
async fn maybe_grow_partition(ui: &Ui, cfg: &Cfg, luks_id: &str) -> Result<bool> {
    let disk = dev(cfg, luks_id);
    let part = part1(cfg, luks_id);
    let disk_bytes = blockdev_bytes(&disk).await?;
    let part_bytes = blockdev_bytes(&part).await?;
    if part_bytes + GROW_THRESHOLD >= disk_bytes {
        return Ok(false);
    }
    ui.state(
        "grow/partition",
        format!("volume {luks_id} was enlarged; extending the partition to fill it"),
    );
    // The backup GPT header sits where the volume used to end; move it to
    // the real end first, or the larger geometry is refused.
    run_ok("sgdisk", &["-e", &disk]).await?;
    // Recreate in place: deleting first makes the old start the first free
    // sector, so "1:0:0" reoccupies exactly the old start and runs to the
    // new end. Type, partuuid and name are restated because a recreated
    // partition carries none of them over.
    run_ok(
        "sgdisk",
        &[
            "-d",
            "1",
            "-n",
            "1:0:0",
            "-t",
            &format!("1:{VAR_TYPE_GUID}"),
            "-u",
            &format!("1:{}", cfg.id.luks_partuuid),
            "-c",
            "1:var",
            &disk,
        ],
    )
    .await?;
    settle().await;
    Ok(true)
}

async fn probe(cfg: &Cfg, id: &str) -> Result<DiskProbe> {
    let p1 = part1(cfg, id);
    let has_part1 = Path::new(&p1).exists();
    Ok(DiskProbe {
        id: id.to_string(),
        has_part1,
        part_fstype: if has_part1 {
            probe_value("blkid", &["-o", "value", "-s", "TYPE", &p1]).await?
        } else {
            None
        },
        part_partuuid: if has_part1 {
            probe_value("lsblk", &["-rno", "PARTUUID", &p1]).await?
        } else {
            None
        },
        disk_pttype: probe_value("blkid", &["-o", "value", "-s", "PTTYPE", &dev(cfg, id)]).await?,
        disk_fstype: probe_value("blkid", &["-o", "value", "-s", "TYPE", &dev(cfg, id)]).await?,
    })
}

fn detail(p: &DiskProbe) -> String {
    if p.has_part1 {
        format!(
            "part1 fstype={} partuuid={}",
            p.part_fstype.as_deref().unwrap_or("-"),
            p.part_partuuid.as_deref().unwrap_or("-")
        )
    } else {
        format!(
            "pttype={} fstype={}",
            p.disk_pttype.as_deref().unwrap_or("-"),
            p.disk_fstype.as_deref().unwrap_or("-")
        )
    }
}

// --- passphrase collection ----------------------------------------------------

async fn ask_new_passphrase(ui: &Ui, cfg: &Cfg) -> String {
    let min = cfg.min_passphrase_len;
    loop {
        let a = ui
            .ask(
                PromptKind::NewPassphrase,
                "New LUKS passphrase for this server's /var volume",
            )
            .await;
        if a.chars().count() < min {
            ui.state(
                "prompt",
                format!("passphrase too short (min {min} chars), asking again"),
            );
            continue;
        }
        let b = ui
            .ask(PromptKind::RepeatPassphrase, "Repeat passphrase")
            .await;
        if a == b {
            return a;
        }
        ui.state("prompt", "passphrases did not match, asking again");
    }
}

// --- disk operations ----------------------------------------------------------

/// GPT + LUKS2 + btrfs on `disk_id`; leaves the mapper open. Only ever
/// called on a disk classified Blank (zero signatures).
async fn format_encrypted(ui: &Ui, cfg: &Cfg, disk_id: &str, passphrase: &str) -> Result<()> {
    let disk = dev(cfg, disk_id);
    ui.state("format/partition", format!("partitioning {disk_id}"));
    run_ok("sgdisk", &["--zap-all", &disk]).await?;
    run_ok(
        "sgdisk",
        &[
            "-n",
            "1:0:0",
            "-t",
            &format!("1:{VAR_TYPE_GUID}"),
            "-u",
            &format!("1:{}", cfg.id.luks_partuuid),
            "-c",
            "1:var",
            &disk,
        ],
    )
    .await?;
    settle().await;
    let part = part1(cfg, disk_id);
    for _ in 0..60 {
        if Path::new(&part).exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    if !Path::new(&part).exists() {
        bail!("partition {part} did not appear");
    }

    ui.state(
        "format/luks",
        format!("creating LUKS2 container on {disk_id}-part1"),
    );
    run_with_stdin(
        "cryptsetup",
        &[
            "luksFormat",
            "--type",
            "luks2",
            "--label",
            "var-crypt",
            "--batch-mode",
            "--key-file",
            "-",
            &part,
        ],
        passphrase,
    )
    .await?;
    run_with_stdin(
        "cryptsetup",
        &[
            "open",
            "--key-file",
            "-",
            "--allow-discards",
            "--persistent",
            &part,
            &cfg.id.mapper,
        ],
        passphrase,
    )
    .await?;

    ui.state(
        "format/mkfs",
        format!("creating btrfs on /dev/mapper/{}", cfg.id.mapper),
    );
    run_ok(
        "mkfs.btrfs",
        &[
            "-L",
            &cfg.id.fs_label,
            &format!("/dev/mapper/{}", cfg.id.mapper),
        ],
    )
    .await?;
    settle().await;
    Ok(())
}

async fn unlock(ui: &Ui, cfg: &Cfg, luks_id: &str) -> Result<()> {
    let part = part1(cfg, luks_id);
    // Before the mapper exists and without key material; the passphrase
    // below is then also the authorization to pull the mapping up to the
    // grown partition. This is the whole online-growth story for LUKS:
    // enlarge the volume, reboot, enter the passphrase as always.
    let grew = maybe_grow_partition(ui, cfg, luks_id).await?;
    let pw = loop {
        let pw = ui
            .ask(
                PromptKind::UnlockPassphrase,
                &format!("Passphrase for /var volume ({luks_id})"),
            )
            .await;
        ui.state("unlock", "unlocking...");
        match run_with_stdin(
            "cryptsetup",
            &[
                "open",
                "--key-file",
                "-",
                "--allow-discards",
                &part,
                &cfg.id.mapper,
            ],
            &pw,
        )
        .await
        {
            Ok(()) => break pw,
            Err(e) => ui.state("unlock", format!("unlock failed ({e}); asking again")),
        }
    };
    settle().await;

    // The mapping follows the partition. Checked by size and not only by
    // `grew`, so a boot that grew the partition but died before this step
    // heals here instead of leaving the gap forever. The passphrase is
    // required: the volume key is in the kernel keyring, not the dm table,
    // so an open mapping alone cannot authorize its own resize.
    let mapper_dev = format!("/dev/mapper/{}", cfg.id.mapper);
    let needs_resize = grew || {
        let part_bytes = blockdev_bytes(&part).await?;
        let mapper_bytes = blockdev_bytes(&mapper_dev).await?;
        mapper_bytes + LUKS_HEADER_SLACK < part_bytes
    };
    if needs_resize {
        ui.state("grow/luks", "extending the LUKS mapping to the grown partition");
        run_with_stdin(
            "cryptsetup",
            &["resize", "--key-file", "-", &cfg.id.mapper],
            &pw,
        )
        .await?;
        settle().await;
    }

    // Post-open content check — a data-loss guard, not a UX nicety.
    // A mapper that opens but holds no btrfs filesystem is ambiguous:
    // usually a half-provisioned volume (earlier boots ran luksFormat but
    // mkfs never ran, e.g. because a missing kernel module failed every
    // `cryptsetup open` until now), but possibly a volume whose filesystem
    // was wiped or corrupted by some OTHER bug. Formatting is only safe in
    // the first case, and only a human can tell them apart — so the manager
    // NEVER formats an empty mapper on its own. Auto-formatting would let a
    // filesystem-destroying bug be silently "repaired" by reformatting on
    // the next reboot, destroying recoverability and masking the bug.
    // Likewise, a failed probe is not proof of emptiness: block, report,
    // and never format.
    let probe = Command::new("blkid")
        .args(["-o", "value", "-s", "TYPE", &mapper_dev])
        .output()
        .await;
    let found = match &probe {
        Ok(out) => mapper_fs_from_blkid(out.status.code(), &String::from_utf8_lossy(&out.stdout)),
        Err(_) => mapper_fs_from_blkid(None, ""),
    };
    match found {
        MapperFs::Btrfs => {
            // The filesystem may still lack the `var` subvolume (mkfs done,
            // subvolume step interrupted — e.g. by an earlier daemon bug or a
            // crash between the two). Creating it is additive and destroys
            // nothing, but a MISSING subvolume on a volume that should hold
            // data signals that something went wrong — same interlock as the
            // empty case: a human decides, the manager never self-heals
            // silently.
            std::fs::create_dir_all("/new-var-fs")?;
            run_ok("mount", &["-o", "subvol=/", &mapper_dev, "/new-var-fs"]).await?;
            // The filesystem follows the mapping, closing the growth chain
            // (volume → partition → mapping → filesystem). A no-op when
            // nothing beneath it changed.
            run_ok("btrfs", &["filesystem", "resize", "max", "/new-var-fs"]).await?;
            let have_subvol = subvol_exists("/new-var-fs/var").await;
            if !have_subvol {
                let yes = ui
                    .ask_confirm(&format!(
                        "Volume {luks_id} has a btrfs filesystem but no 'var' subvolume \
                         (the boot mounts subvol=var). Create it now? This is additive and \
                         erases nothing. Only expected on a fresh/half-provisioned volume; \
                         if this volume should already hold data, answer n and investigate. \
                         [y/n]"
                    ))
                    .await;
                if yes {
                    run_ok("btrfs", &["subvolume", "create", "/new-var-fs/var"]).await?;
                } else {
                    run_ok("umount", &["/new-var-fs"]).await?;
                    match ui
                        .block_forever(&format!(
                            "volume {luks_id} has btrfs but no 'var' subvolume and the \
                             operator DECLINED to create it. Nothing was written. \
                             Investigate (mapper open at {mapper_dev}), or power-cycle to \
                             be asked again."
                        ))
                        .await {}
                }
            }
            run_ok("umount", &["/new-var-fs"]).await?;
        }
        MapperFs::Empty => {
            let yes = ui
                .ask_confirm(&format!(
                    "Volume {luks_id} is unlocked but contains no filesystem. Format it as \
                     btrfs (label {})? This erases nothing — the volume is empty. This is \
                     only safe if this is a fresh/half-provisioned volume; if you expected \
                     data here, answer n and investigate (nothing will be written on n). [y/n]",
                    cfg.id.fs_label
                ))
                .await;
            if yes {
                ui.state("format/mkfs", format!("creating btrfs on {mapper_dev}"));
                run_ok("mkfs.btrfs", &["-L", &cfg.id.fs_label, &mapper_dev]).await?;
                settle().await;
                create_var_subvol(cfg).await?;
            } else {
                match ui
                    .block_forever(&format!(
                        "volume {luks_id} is unlocked but has no filesystem and the operator \
                         DECLINED to format it. Nothing was written; the volume is untouched. \
                         If this volume should hold data, investigate now — the mapper is \
                         still open at {mapper_dev}. To format manually: mkfs.btrfs -L {} \
                         {mapper_dev}, then reboot. Or simply power-cycle to be asked again.",
                        cfg.id.fs_label
                    ))
                    .await {}
            }
        }
        MapperFs::Other(fstype) => {
            match ui
                .block_forever(&format!(
                    "volume {luks_id} is unlocked but contains an unexpected filesystem type \
                     '{fstype}' (expected btrfs). NOT touching it; investigate manually and \
                     power-cycle."
                ))
                .await {}
        }
        MapperFs::Unknown => {
            match ui
                .block_forever(&format!(
                    "volume {luks_id} is unlocked but its contents could not be determined \
                     (blkid probe on {mapper_dev} failed). Emptiness is NOT established, so \
                     nothing will be written. Investigate manually and power-cycle."
                ))
                .await {}
        }
    }
    ui.state("unlock", "unlocked; boot continuing");
    Ok(())
}

async fn ensure_label(ui: &Ui, cfg: &Cfg, legacy_id: &str) -> Result<()> {
    let part = part1(cfg, legacy_id);
    let label = probe_value("blkid", &["-o", "value", "-s", "LABEL", &part]).await?;
    if label.as_deref() != Some(cfg.id.fs_label.as_str()) {
        ui.state("legacy", "labeling legacy filesystem");
        run_ok("btrfs", &["filesystem", "label", &part, &cfg.id.fs_label]).await?;
        let _ = Command::new("udevadm")
            .args(["trigger", "--settle", &part])
            .status()
            .await;
    }
    ui.state("legacy", "booting unencrypted (pre-migration)");
    Ok(())
}

async fn subvol_exists(path: &str) -> bool {
    Command::new("btrfs")
        .args(["subvolume", "show", path])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .await
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Pump `btrfs send | btrfs receive` through the daemon, counting bytes.
async fn copy_with_progress(ui: &Ui, total: u64) -> Result<()> {
    let mut send = Command::new("btrfs")
        .args(["send", "/old/.migrate-src"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("spawning btrfs send")?;
    let mut recv = Command::new("btrfs")
        .args(["receive", "/new/"])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .context("spawning btrfs receive")?;

    // Drain both stderr pipes CONCURRENTLY with the copy: a child blocked
    // writing to a full, unread stderr pipe deadlocks the whole pipeline
    // (the shell version inherited stderr and had no such hazard).
    async fn drain(r: Option<impl AsyncReadExt + Unpin>) -> String {
        let mut buf = Vec::new();
        if let Some(mut r) = r {
            let _ = r.read_to_end(&mut buf).await;
        }
        String::from_utf8_lossy(&buf).trim().to_string()
    }
    let send_stderr = tokio::spawn(drain(send.stderr.take()));
    let recv_stderr = tokio::spawn(drain(recv.stderr.take()));

    let mut from = send.stdout.take().context("send stdout")?;
    let mut to = recv.stdin.take().context("receive stdin")?;

    let pump = async {
        let mut buf = vec![0u8; 1 << 20];
        let mut copied: u64 = 0;
        let mut last_update = std::time::Instant::now();
        loop {
            let n = from
                .read(&mut buf)
                .await
                .context("reading from btrfs send")?;
            if n == 0 {
                break;
            }
            to.write_all(&buf[..n])
                .await
                .context("writing to btrfs receive")?;
            copied += n as u64;
            if last_update.elapsed() > Duration::from_millis(200) {
                ui.progress(copied.min(total), total);
                last_update = std::time::Instant::now();
            }
        }
        Ok::<_, anyhow::Error>(())
    };
    let pump_result = pump.await;
    drop(to); // EOF for receive

    if pump_result.is_err() {
        // One side died mid-copy; the other may now be blocked on a pipe
        // nobody services. Kill both so wait() below cannot hang.
        let _ = send.kill().await;
        let _ = recv.kill().await;
    }
    let send_status = send.wait().await.context("waiting for btrfs send")?;
    let recv_status = recv.wait().await.context("waiting for btrfs receive")?;
    let send_stderr = send_stderr.await.unwrap_or_default();
    let recv_stderr = recv_stderr.await.unwrap_or_default();

    if let Err(e) = pump_result {
        bail!("copy failed: {e:#}; btrfs send: {send_stderr}; btrfs receive: {recv_stderr}");
    }
    if !send_status.success() {
        bail!("btrfs send failed ({send_status}): {send_stderr}");
    }
    if !recv_status.success() {
        bail!("btrfs receive failed ({recv_status}): {recv_stderr}");
    }
    ui.progress(total, total);
    Ok(())
}

async fn migrate(
    ui: &Ui,
    cfg: &Cfg,
    legacy_id: &str,
    blank_id: &str,
) -> Result<std::convert::Infallible> {
    let legacy_part = part1(cfg, legacy_id);
    std::fs::create_dir_all("/old")?;
    std::fs::create_dir_all("/new")?;

    ui.state("migrate/inspect", "migration: inspecting source");
    run_ok("mount", &["-o", "subvol=/", &legacy_part, "/old"]).await?;
    // A leftover snapshot from an interrupted attempt pins extents and
    // inflates the usage figure; clean it up before the size check.
    if subvol_exists("/old/.migrate-src").await {
        run_ok("btrfs", &["subvolume", "delete", "/old/.migrate-src"]).await?;
        run_ok("sync", &[]).await?;
    }
    let usage = run_ok("btrfs", &["filesystem", "usage", "-b", "/old"]).await?;
    let Some(used) = parse_btrfs_used(&usage) else {
        let _ = run_ok("umount", &["/old"]).await;
        match ui
            .block_forever("MIGRATION ABORTED: could not determine used bytes on the source")
            .await {}
    };
    let size_out = run_ok("blockdev", &["--getsize64", &dev(cfg, blank_id)]).await?;
    let target: u64 = size_out.trim().parse().context("parsing blockdev output")?;
    let needed = used + SIZE_HEADROOM;
    if target < needed {
        let _ = run_ok("umount", &["/old"]).await;
        match ui
            .block_forever(&format!(
                "MIGRATION ABORTED: new volume ({target} bytes) smaller than used data + 1GiB \
                 headroom ({needed} bytes). Attach a bigger volume and power-cycle."
            ))
            .await {}
    }

    let passphrase = ask_new_passphrase(ui, cfg).await;
    format_encrypted(ui, cfg, blank_id, &passphrase).await?;

    ui.state("migrate/copy", "copying /var (btrfs send/receive)");
    run_ok(
        "btrfs",
        &[
            "subvolume",
            "snapshot",
            "-r",
            "/old/var",
            "/old/.migrate-src",
        ],
    )
    .await?;
    run_ok("sync", &[]).await?;
    run_ok(
        "mount",
        &[
            "-o",
            "subvol=/",
            &format!("/dev/mapper/{}", cfg.id.mapper),
            "/new",
        ],
    )
    .await?;
    copy_with_progress(ui, used).await?;
    // btrfs-progs 6.x refuses to flip a received subvolume rw; a rw
    // snapshot of it drops received_uuid, fine — no incremental sends.
    run_ok(
        "btrfs",
        &["subvolume", "snapshot", "/new/.migrate-src", "/new/var"],
    )
    .await?;
    run_ok("btrfs", &["subvolume", "delete", "/new/.migrate-src"]).await?;

    ui.state("migrate/cleanup", "migration: cleaning up");
    run_ok("btrfs", &["subvolume", "delete", "/old/.migrate-src"]).await?;
    run_ok("sync", &[]).await?;
    run_ok("umount", &["/new"]).await?;
    run_ok("umount", &["/old"]).await?;
    run_ok("cryptsetup", &["close", &cfg.id.mapper]).await?;

    ui.mutate(|s| s.progress = None);
    Ok(ui
        .block_forever(&format!(
            "MIGRATION COMPLETE. Detach the old volume ({legacy_id}) from this machine, then \
             power-cycle. Do NOT delete the old volume until the server is verified healthy."
        ))
        .await)
}

async fn provision(ui: &Ui, cfg: &Cfg, blank_id: &str) -> Result<()> {
    ui.state("provision", "fresh server: provisioning encrypted /var");
    let passphrase = ask_new_passphrase(ui, cfg).await;
    format_encrypted(ui, cfg, blank_id, &passphrase).await?;
    create_var_subvol(cfg).await?;
    ui.state("provision", "provisioned; boot continuing");
    Ok(())
}

/// Create the `var` subvolume the main system mounts. mkfs.btrfs alone is not
/// enough: fstab mounts by label with `subvol=var`, so a filesystem without
/// this subvolume fails sysroot-var.mount and drops the boot to emergency.
async fn create_var_subvol(cfg: &Cfg) -> Result<()> {
    std::fs::create_dir_all("/new-var-fs")?;
    run_ok(
        "mount",
        &[
            "-o",
            "subvol=/",
            &format!("/dev/mapper/{}", cfg.id.mapper),
            "/new-var-fs",
        ],
    )
    .await?;
    run_ok("btrfs", &["subvolume", "create", "/new-var-fs/var"]).await?;
    run_ok("umount", &["/new-var-fs"]).await?;
    Ok(())
}

// --- socket server ------------------------------------------------------------

async fn serve_client(
    stream: UnixStream,
    mut rx: watch::Receiver<Snapshot>,
    tx_submit: mpsc::UnboundedSender<ClientMsg>,
) {
    let (read_half, mut write_half) = stream.into_split();
    let mut lines = BufReader::new(read_half).lines();

    // Reader: client -> daemon submissions.
    let reader = tokio::spawn(async move {
        while let Ok(Some(line)) = lines.next_line().await {
            if let Ok(msg) = serde_json::from_str::<ClientMsg>(&line) {
                let _ = tx_submit.send(msg);
            }
        }
    });

    // Writer: initial snapshot + every change.
    loop {
        let snap = rx.borrow_and_update().clone();
        let mut json = match serde_json::to_string(&snap) {
            Ok(j) => j,
            Err(_) => break,
        };
        json.push('\n');
        if write_half.write_all(json.as_bytes()).await.is_err() {
            break;
        }
        if rx.changed().await.is_err() {
            break;
        }
    }
    reader.abort();
}

// --- main -----------------------------------------------------------------------

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let result = run().await;
    if let Err(e) = &result {
        let msg = format!("FAILED: {e:#}");
        eprintln!("var-disk-manager: {msg}");
        let _ = std::fs::write(STATE_FILE, format!("{msg}\n"));
        // Failure is loud on purpose (no <7>): the console TUI is about to
        // be stopped by emergency.target anyway, and this line must be
        // visible there.
        let _ = std::fs::write("/dev/kmsg", format!("var-disk-manager: {msg}\n"));
        std::process::exit(1);
    }
}

async fn run() -> Result<()> {
    let cli = Cli::parse();
    let Some((by_id_dir, prefix)) = split_prefix_glob(&cli.volume_glob) else {
        bail!(
            "--volume-glob must have the form <dir>/<prefix>* (got: {})",
            cli.volume_glob
        );
    };
    let cfg = Cfg {
        by_id_dir,
        prefix,
        id: Identity {
            luks_partuuid: cli.luks_partuuid,
            fs_label: cli.fs_label,
            mapper: cli.mapper,
        },
        min_passphrase_len: cli.min_passphrase_len,
    };

    for tool in REQUIRED_TOOLS {
        // `which`-style lookup against our own PATH.
        let found = std::env::var_os("PATH")
            .map(|p| std::env::split_paths(&p).any(|d| d.join(tool).exists()))
            .unwrap_or(false);
        if !found {
            bail!("required tool missing from initrd: {tool}");
        }
    }

    std::fs::create_dir_all("/run/var-disk-manager")?;
    let _ = std::fs::remove_file(SOCKET_PATH);
    let listener = UnixListener::bind(SOCKET_PATH).context("binding control socket")?;

    let (tx, _) = watch::channel(Snapshot::default());
    let (tx_submit, rx_submit) = mpsc::unbounded_channel();
    let ui: &'static Ui = Box::leak(Box::new(Ui {
        snapshot: Mutex::new(Snapshot::default()),
        tx,
        submissions: Mutex::new(rx_submit),
        next_prompt_id: Mutex::new(0),
    }));

    // Accept TUI clients for the lifetime of the daemon.
    let rx_factory = ui.tx.subscribe();
    tokio::spawn(async move {
        loop {
            if let Ok((stream, _)) = listener.accept().await {
                tokio::spawn(serve_client(stream, rx_factory.clone(), tx_submit.clone()));
            }
        }
    });

    // Fingerprint of the initrd SSH host key, once it exists (written by
    // the initrd-ssh host-key oneshot — soft coupling, absent is fine).
    tokio::spawn(async move {
        for _ in 0..60 {
            if let Ok(out) = run_ok("ssh-keygen", &["-lf", "/etc/ssh/ssh_host_ed25519_key"]).await {
                ui.mutate(|s| s.fingerprint = Some(out.trim().to_string()));
                return;
            }
            tokio::time::sleep(Duration::from_secs(3)).await;
        }
    });

    // Wait for at least one data disk, then for the set to stop growing:
    // a just-attached migration volume can enumerate noticeably later
    // than the long-attached one.
    ui.state("enumerate", "waiting for data volumes");
    settle().await;
    let mut stable = 0;
    let mut prev = 0usize;
    for _ in 0..90 {
        let count = list_volumes(&cfg).len();
        if count > 0 && count == prev {
            stable += 1;
            if stable >= 5 {
                break;
            }
        } else {
            stable = 0;
        }
        prev = count;
        tokio::time::sleep(Duration::from_secs(1)).await;
    }

    ui.state("classify", "classifying data volumes");
    let mut infos = vec![];
    let mut classes = vec![];
    for id in list_volumes(&cfg) {
        let p = probe(&cfg, &id).await?;
        let class = classify(&p, &cfg.id.luks_partuuid);
        if class == DiskClass::Foreign {
            ui.state(
                "classify",
                format!("ignoring foreign volume {id} ({})", detail(&p)),
            );
        }
        infos.push(DiskInfo {
            id: id.clone(),
            class,
            detail: detail(&p),
        });
        classes.push((id, class));
    }
    ui.mutate(|s| s.disks = infos);

    match plan(&classes) {
        Plan::Unlock { luks } => unlock(ui, &cfg, &luks).await,
        Plan::BootLegacy { legacy } => ensure_label(ui, &cfg, &legacy).await,
        Plan::Migrate { legacy, blank } => match migrate(ui, &cfg, &legacy, &blank).await {
            Ok(never) => match never {},
            Err(e) => Err(e),
        },
        Plan::Provision { blank } => provision(ui, &cfg, &blank).await,
        Plan::Block { reason } => match ui.block_forever(&reason).await {},
        Plan::NoDisks => bail!("no data volume found"),
    }
}

//! Shared protocol and the pure disk-classification logic.
//!
//! The daemon (`var-disk-managerd`) owns the state machine; TUI clients
//! (`var-disk-manager-tui`) connect over a unix socket and receive
//! [`Snapshot`]s as newline-delimited JSON, sending [`ClientMsg`]s back.
//! Classification and planning are pure functions over probe results so
//! every disk-set permutation is unit-testable — including the failure
//! modes that bit the shell implementation (a missing probe tool must
//! never look like a blank disk).

use serde::{Deserialize, Serialize};

pub const SOCKET_PATH: &str = "/run/var-disk-manager/sock";
pub const STATE_FILE: &str = "/run/var-disk-manager/state";

/// systemd discoverable-partitions type GUID for /var (x86-64) — a spec
/// constant, not configuration; foundrix images also use it as the legacy
/// var partition's PARTUUID.
pub const VAR_TYPE_GUID: &str = "4d21b016-b534-45c2-a9fb-5c16e091fd2d";

/// Deployment identity, provided by the nix module via daemon CLI flags
/// (nix is the single source of truth; these only carry the values).
#[derive(Clone, Debug)]
pub struct Identity {
    /// PARTUUID the manager assigns to (and requires of) the LUKS partition.
    pub luks_partuuid: String,
    /// btrfs filesystem label /var is mounted by.
    pub fs_label: String,
    /// dm mapper name for the opened LUKS volume.
    pub mapper: String,
}

// --- wire protocol ---------------------------------------------------------

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
pub enum DiskClass {
    Luks,
    Legacy,
    Blank,
    Foreign,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct DiskInfo {
    /// by-id basename of the whole-disk device link.
    pub id: String,
    pub class: DiskClass,
    /// Human-readable probe detail (fstype, partuuid...).
    pub detail: String,
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
pub enum PromptKind {
    /// Existing volume: single passphrase entry.
    UnlockPassphrase,
    /// New volume: first entry.
    NewPassphrase,
    /// New volume: confirmation entry.
    RepeatPassphrase,
    /// Yes/no operator decision. The submission is still a free-form
    /// String over the same ClientMsg::Submit protocol ("y"/"yes"/"n"/"no",
    /// case-insensitive); the TUI renders it unmasked and submits on a
    /// single keypress.
    Confirm,
}

/// Parse a [`PromptKind::Confirm`] answer. Returns None for anything that
/// is not an unambiguous yes or no — the caller re-prompts.
pub fn parse_confirm(answer: &str) -> Option<bool> {
    match answer.trim().to_ascii_lowercase().as_str() {
        "y" | "yes" => Some(true),
        "n" | "no" => Some(false),
        _ => None,
    }
}

/// What a `blkid` TYPE probe found inside an OPENED LUKS mapper.
///
/// The distinctions here are a data-loss guard, not a UX nicety: an
/// unlocked-but-empty mapper is ambiguous. It is usually a half-provisioned
/// volume (luksFormat succeeded, mkfs never ran), but it could equally be a
/// volume whose filesystem was wiped or corrupted by some OTHER bug — and
/// auto-formatting that case on a random reboot would silently destroy
/// recoverability and mask the original bug. The daemon must therefore only
/// ever format [`MapperFs::Empty`], and only after explicit operator
/// confirmation; [`MapperFs::Unknown`] means emptiness was NOT established
/// and must block, never format.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MapperFs {
    /// Steady state: a btrfs filesystem is present.
    Btrfs,
    /// blkid ran cleanly and found no signatures (exit 2).
    Empty,
    /// A filesystem (or other signature) that is not btrfs — never ours
    /// to touch.
    Other(String),
    /// The probe failed or was inconclusive; nothing is proven.
    Unknown,
}

/// Interpret the result of `blkid -o value -s TYPE <mapper>`. `exit` is
/// blkid's exit code (None if it could not even be spawned), `stdout` its
/// standard output. Only exit 2 ("nothing found") counts as Empty; any
/// other failure is [`MapperFs::Unknown`].
pub fn mapper_fs_from_blkid(exit: Option<i32>, stdout: &str) -> MapperFs {
    match (exit, stdout.trim()) {
        (Some(0), "btrfs") => MapperFs::Btrfs,
        // Success with no TYPE printed shouldn't happen; don't guess.
        (Some(0), "") => MapperFs::Unknown,
        (Some(0), other) => MapperFs::Other(other.to_string()),
        (Some(2), _) => MapperFs::Empty,
        _ => MapperFs::Unknown,
    }
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Prompt {
    pub id: u64,
    pub kind: PromptKind,
    pub text: String,
}

#[derive(Serialize, Deserialize, Clone, Copy, Debug)]
pub struct Progress {
    pub copied: u64,
    pub total: u64,
}

/// Full UI state; the daemon sends a fresh one on every change.
#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct Snapshot {
    /// Short phase tag, e.g. `classify`, `migrate/copy`, `blocked`.
    pub phase: String,
    /// One human-readable line; mirrored into the state file.
    pub message: String,
    /// Terminal block state: the boot will not proceed, ever.
    pub blocked: bool,
    pub disks: Vec<DiskInfo>,
    pub progress: Option<Progress>,
    pub prompt: Option<Prompt>,
    /// initrd SSH host key fingerprint, for the visual MITM check.
    pub fingerprint: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub enum ClientMsg {
    Submit { prompt_id: u64, value: String },
}

// --- classification (pure) -------------------------------------------------

/// Raw probe results for one whole disk. `None` means the probe ran and
/// found nothing; a probe that could not run at all must abort the boot
/// long before this point (tool preflight).
#[derive(Clone, Debug, Default)]
pub struct DiskProbe {
    pub id: String,
    pub has_part1: bool,
    /// blkid TYPE of partition 1 (e.g. `crypto_LUKS`, `btrfs`).
    pub part_fstype: Option<String>,
    /// PARTUUID of partition 1.
    pub part_partuuid: Option<String>,
    /// blkid PTTYPE of the whole disk (partition table present).
    pub disk_pttype: Option<String>,
    /// blkid TYPE of the whole disk (whole-disk filesystem present).
    pub disk_fstype: Option<String>,
}

pub fn classify(p: &DiskProbe, luks_partuuid: &str) -> DiskClass {
    if p.has_part1 {
        let fstype = p.part_fstype.as_deref().unwrap_or("");
        let partuuid = p.part_partuuid.as_deref().unwrap_or("");
        if fstype == "crypto_LUKS" && partuuid.eq_ignore_ascii_case(luks_partuuid) {
            DiskClass::Luks
        } else if fstype == "btrfs" && partuuid.eq_ignore_ascii_case(VAR_TYPE_GUID) {
            DiskClass::Legacy
        } else {
            DiskClass::Foreign
        }
    } else if p.disk_pttype.is_none() && p.disk_fstype.is_none() {
        // Zero signatures, zero partition table: the only thing the
        // manager will ever write to.
        DiskClass::Blank
    } else {
        DiskClass::Foreign
    }
}

/// What the state machine should do, decided from the full disk set.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Plan {
    /// Steady state: ask passphrase, attach, boot.
    Unlock { luks: String },
    /// Pre-migration compatibility: boot unencrypted.
    BootLegacy { legacy: String },
    /// legacy + blank: migrate, then block.
    Migrate { legacy: String, blank: String },
    /// Fresh server: format the blank disk, boot.
    Provision { blank: String },
    /// Never boot; show the reason until power-cycled.
    Block { reason: String },
    /// No usable disk at all: fail to emergency.
    NoDisks,
}

pub fn plan(disks: &[(String, DiskClass)]) -> Plan {
    let mut luks: Vec<&str> = vec![];
    let mut legacy: Vec<&str> = vec![];
    let mut blank: Vec<&str> = vec![];
    for (id, class) in disks {
        match class {
            DiskClass::Luks => luks.push(id),
            DiskClass::Legacy => legacy.push(id),
            DiskClass::Blank => blank.push(id),
            DiskClass::Foreign => {}
        }
    }

    for (kind, list) in [("LUKS", &luks), ("legacy var", &legacy), ("blank", &blank)] {
        if list.len() > 1 {
            return Plan::Block {
                reason: format!(
                    "multiple {kind} volumes attached ({}); detach the extra volume and power-cycle",
                    list.join(", ")
                ),
            };
        }
    }

    match (luks.first(), legacy.first(), blank.first()) {
        (Some(l), Some(old), _) => Plan::Block {
            reason: format!(
                "UNENCRYPTED DISK STILL ATTACHED: detach old volume {old} from this machine \
                 and power-cycle (encrypted volume {l} stays)"
            ),
        },
        (Some(l), None, _) => Plan::Unlock {
            luks: l.to_string(),
        },
        (None, Some(old), Some(new)) => Plan::Migrate {
            legacy: old.to_string(),
            blank: new.to_string(),
        },
        (None, Some(old), None) => Plan::BootLegacy {
            legacy: old.to_string(),
        },
        (None, None, Some(new)) => Plan::Provision {
            blank: new.to_string(),
        },
        (None, None, None) => Plan::NoDisks,
    }
}

/// Split a volume glob of the form `<dir>/<prefix>*` (the only supported
/// shape) into (dir, prefix). Returns None for anything else.
pub fn split_prefix_glob(glob: &str) -> Option<(String, String)> {
    let rest = glob.strip_suffix('*')?;
    // No other wildcard characters permitted anywhere in the pattern.
    if rest.contains(['*', '?', '[']) {
        return None;
    }
    let (dir, prefix) = rest.rsplit_once('/')?;
    if dir.is_empty() || prefix.is_empty() {
        return None;
    }
    Some((dir.to_string(), prefix.to_string()))
}

/// Parse the `Used:` figure out of `btrfs filesystem usage -b` output.
/// Returns None (never a silent 0) when the format is unrecognized.
pub fn parse_btrfs_used(output: &str) -> Option<u64> {
    output.lines().find_map(|line| {
        let t = line.trim_start();
        if t.starts_with("Used:") && line.starts_with(char::is_whitespace) {
            t.strip_prefix("Used:")?.trim().parse().ok()
        } else {
            None
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_LUKS_PARTUUID: &str = "cab17794-a0a1-4908-8dd2-3f205a938611";

    fn luks_disk(id: &str) -> DiskProbe {
        DiskProbe {
            id: id.into(),
            has_part1: true,
            part_fstype: Some("crypto_LUKS".into()),
            part_partuuid: Some(TEST_LUKS_PARTUUID.to_uppercase()),
            ..Default::default()
        }
    }

    fn legacy_disk(id: &str) -> DiskProbe {
        DiskProbe {
            id: id.into(),
            has_part1: true,
            part_fstype: Some("btrfs".into()),
            part_partuuid: Some(VAR_TYPE_GUID.into()),
            ..Default::default()
        }
    }

    fn blank_disk(id: &str) -> DiskProbe {
        DiskProbe {
            id: id.into(),
            ..Default::default()
        }
    }

    fn classified(probes: &[DiskProbe]) -> Vec<(String, DiskClass)> {
        probes
            .iter()
            .map(|p| (p.id.clone(), classify(p, TEST_LUKS_PARTUUID)))
            .collect()
    }

    #[test]
    fn classify_the_three_kinds() {
        assert_eq!(
            classify(&luks_disk("a"), TEST_LUKS_PARTUUID),
            DiskClass::Luks
        );
        assert_eq!(
            classify(&legacy_disk("a"), TEST_LUKS_PARTUUID),
            DiskClass::Legacy
        );
        assert_eq!(
            classify(&blank_disk("a"), TEST_LUKS_PARTUUID),
            DiskClass::Blank
        );
    }

    #[test]
    fn foreign_luks_partuuid_mismatch() {
        // A crypto_LUKS partition without our PARTUUID is not ours.
        let mut p = luks_disk("a");
        p.part_partuuid = Some("11111111-2222-3333-4444-555555555555".into());
        assert_eq!(classify(&p, TEST_LUKS_PARTUUID), DiskClass::Foreign);
    }

    #[test]
    fn foreign_btrfs_partuuid_mismatch() {
        let mut p = legacy_disk("a");
        p.part_partuuid = Some("11111111-2222-3333-4444-555555555555".into());
        assert_eq!(classify(&p, TEST_LUKS_PARTUUID), DiskClass::Foreign);
    }

    #[test]
    fn empty_gpt_is_foreign_not_blank() {
        // Partitioned-but-empty (e.g. a provider "pre-formatted" volume)
        // must never be treated as a format target.
        let p = DiskProbe {
            id: "a".into(),
            disk_pttype: Some("gpt".into()),
            ..Default::default()
        };
        assert_eq!(classify(&p, TEST_LUKS_PARTUUID), DiskClass::Foreign);
    }

    #[test]
    fn whole_disk_filesystem_is_foreign() {
        let p = DiskProbe {
            id: "a".into(),
            disk_fstype: Some("ext4".into()),
            ..Default::default()
        };
        assert_eq!(classify(&p, TEST_LUKS_PARTUUID), DiskClass::Foreign);
    }

    #[test]
    fn missing_probe_values_never_mean_blank_when_partitioned() {
        // has_part1 with no fstype (e.g. an unformatted partition):
        // foreign, not blank, not legacy.
        let p = DiskProbe {
            id: "a".into(),
            has_part1: true,
            ..Default::default()
        };
        assert_eq!(classify(&p, TEST_LUKS_PARTUUID), DiskClass::Foreign);
    }

    #[test]
    fn plan_steady_state() {
        let d = classified(&[luks_disk("l")]);
        assert_eq!(plan(&d), Plan::Unlock { luks: "l".into() });
    }

    #[test]
    fn plan_pre_migration() {
        let d = classified(&[legacy_disk("old")]);
        assert_eq!(
            plan(&d),
            Plan::BootLegacy {
                legacy: "old".into()
            }
        );
    }

    #[test]
    fn plan_migration() {
        let d = classified(&[legacy_disk("old"), blank_disk("new")]);
        assert_eq!(
            plan(&d),
            Plan::Migrate {
                legacy: "old".into(),
                blank: "new".into()
            }
        );
    }

    #[test]
    fn plan_blocks_when_old_disk_still_attached() {
        let d = classified(&[legacy_disk("old"), luks_disk("l")]);
        assert!(matches!(plan(&d), Plan::Block { .. }));
        // ... even with a blank one also present.
        let d = classified(&[legacy_disk("old"), luks_disk("l"), blank_disk("new")]);
        assert!(matches!(plan(&d), Plan::Block { .. }));
    }

    #[test]
    fn plan_provision_fresh_server() {
        let d = classified(&[blank_disk("new")]);
        assert_eq!(
            plan(&d),
            Plan::Provision {
                blank: "new".into()
            }
        );
    }

    #[test]
    fn plan_blocks_on_duplicates() {
        for dup in [
            classified(&[luks_disk("a"), luks_disk("b")]),
            classified(&[legacy_disk("a"), legacy_disk("b")]),
            classified(&[blank_disk("a"), blank_disk("b")]),
            // Mixed duplicates: multiple kinds over-represented at once
            // still block, whichever guard fires first.
            classified(&[
                luks_disk("a"),
                luks_disk("b"),
                legacy_disk("c"),
                legacy_disk("d"),
            ]),
            classified(&[
                luks_disk("a"),
                luks_disk("b"),
                blank_disk("c"),
                blank_disk("d"),
            ]),
            classified(&[
                legacy_disk("a"),
                legacy_disk("b"),
                blank_disk("c"),
                blank_disk("d"),
            ]),
        ] {
            assert!(matches!(plan(&dup), Plan::Block { .. }), "{dup:?}");
        }
    }

    #[test]
    fn plan_foreign_only_is_no_disks() {
        let p = DiskProbe {
            id: "weird".into(),
            disk_pttype: Some("dos".into()),
            ..Default::default()
        };
        let d = classified(&[p]);
        assert_eq!(plan(&d), Plan::NoDisks);
    }

    #[test]
    fn plan_luks_plus_blank_unlocks_and_ignores_blank() {
        let d = classified(&[luks_disk("l"), blank_disk("scratch")]);
        assert_eq!(plan(&d), Plan::Unlock { luks: "l".into() });
    }

    #[test]
    fn glob_splits_prefix_form() {
        assert_eq!(
            split_prefix_glob("/dev/disk/by-id/scsi-0HC_Volume_*"),
            Some(("/dev/disk/by-id".into(), "scsi-0HC_Volume_".into()))
        );
        assert_eq!(
            split_prefix_glob("/dev/disk/by-id/virtio-data-*"),
            Some(("/dev/disk/by-id".into(), "virtio-data-".into()))
        );
    }

    #[test]
    fn glob_rejects_unsupported_shapes() {
        for bad in [
            "/dev/disk/by-id/scsi-0HC_Volume_", // no wildcard
            "/dev/disk/by-id/*",                // empty prefix
            "/dev/*/scsi-*",                    // wildcard outside the tail
            "scsi-0HC_Volume_*",                // no directory
            "/dev/disk/by-id/vol?*",            // other wildcard chars
            "",
        ] {
            assert_eq!(split_prefix_glob(bad), None, "{bad}");
        }
    }

    #[test]
    fn btrfs_used_parses_real_output() {
        let out = "Overall:\n    Device size:          36835028992\n    \
                   Device allocated:      9128378368\n    Used:          6296619008\n";
        assert_eq!(parse_btrfs_used(out), Some(6_296_619_008));
    }

    #[test]
    fn btrfs_used_rejects_garbage() {
        assert_eq!(parse_btrfs_used(""), None);
        assert_eq!(parse_btrfs_used("Used: banana"), None);
        // A `Used:` line with no leading whitespace is not the Overall figure.
        assert_eq!(parse_btrfs_used("Used: 123"), None);
    }

    #[test]
    fn confirm_parses_yes_and_no() {
        for yes in ["y", "Y", "yes", "YES", " Yes ", "yEs"] {
            assert_eq!(parse_confirm(yes), Some(true), "{yes}");
        }
        for no in ["n", "N", "no", "NO", " No ", "nO"] {
            assert_eq!(parse_confirm(no), Some(false), "{no}");
        }
    }

    #[test]
    fn confirm_rejects_ambiguous_answers() {
        for bad in ["", "maybe", "yn", "1", "0", "yesno", "on", "off", "  "] {
            assert_eq!(parse_confirm(bad), None, "{bad}");
        }
    }

    #[test]
    fn mapper_fs_empty_only_on_clean_nothing_found() {
        // blkid exit 2: probe ran, found no signatures -> Empty.
        assert_eq!(mapper_fs_from_blkid(Some(2), ""), MapperFs::Empty);
        assert_eq!(mapper_fs_from_blkid(Some(0), "btrfs\n"), MapperFs::Btrfs);
        assert_eq!(
            mapper_fs_from_blkid(Some(0), "ext4"),
            MapperFs::Other("ext4".into())
        );
        // Every failure shape is Unknown, never Empty: a failed probe is
        // not proof the mapper is empty.
        for unknown in [(Some(1), ""), (Some(0), ""), (Some(32), ""), (None, "")] {
            assert_eq!(
                mapper_fs_from_blkid(unknown.0, unknown.1),
                MapperFs::Unknown
            );
        }
    }

    #[test]
    fn snapshot_roundtrip() {
        let s = Snapshot {
            phase: "migrate/copy".into(),
            message: "copying".into(),
            blocked: false,
            disks: vec![DiskInfo {
                id: "d".into(),
                class: DiskClass::Legacy,
                detail: "btrfs".into(),
            }],
            progress: Some(Progress {
                copied: 1,
                total: 2,
            }),
            prompt: Some(Prompt {
                id: 7,
                kind: PromptKind::NewPassphrase,
                text: "pw".into(),
            }),
            fingerprint: Some("SHA256:abc".into()),
        };
        let json = serde_json::to_string(&s).unwrap();
        let back: Snapshot = serde_json::from_str(&json).unwrap();
        assert_eq!(back.prompt.unwrap().id, 7);
        assert_eq!(back.progress.unwrap().total, 2);
    }
}

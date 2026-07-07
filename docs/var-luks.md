# Encrypted /var: `config/filesystem/var-luks.nix`

Provides `/var` as btrfs inside a LUKS2 container on a dedicated data
volume, with a passphrase entered at boot on the machine console or over
initrd SSH. Includes a fully automatic, resumable migration path from an
unencrypted volume created by `runtime/repart/var.nix`, so existing
deployments can be converted by attaching one disk and rebooting.

Threat model: data at rest — disk disposal, volume snapshots, offline
theft, storage-level compromise. NOT covered: a live-compromised host or
a tampered initrd (the initrd necessarily stays on unencrypted storage).

## Pieces

- **`packages/var-disk-manager`** — a Rust daemon (`var-disk-managerd`)
  plus a ratatui client (`var-disk-manager-tui`). The daemon runs as a
  oneshot initrd unit, classifies the data volumes and acts (below); it
  serves live state over a unix socket (`/run/var-disk-manager/sock`).
  The TUI renders that state fullscreen; it runs on `/dev/console` *and*
  as the initrd SSH login shell — every session sees the same screen and
  any of them can answer the passphrase prompt. Deployment identity
  (volume glob, LUKS PARTUUID, label, mapper) is passed as CLI flags;
  the nix module is the single source of truth.
- **`config/filesystem/var-luks.nix`** — wires the daemon into the
  initrd, mounts `/var` by filesystem label, and announces
  `foundrix.traits.filesystem.varProvisioner = luks-manager`.
- **`config/initrd/ssh.nix`** (imported by var-luks, usable standalone) —
  sshd in the systemd initrd on its own port (default 2222) with its own
  host key, generated on first boot and persisted on the ESP: no
  known-hosts collisions with the main sshd, no keys in the nix store.
  The fingerprint is shown in the TUI on the (trusted) console for a
  visual MITM check, and logged to kmsg at debug level.

## The state machine

Volumes matching `volumeGlob` (whole-disk by-id links, shape
`<dir>/<prefix>*`) are classified by **content**, never attach order:
`crypto_LUKS` + the configured PARTUUID → **LUKS**; btrfs + the
discoverable-partitions var type GUID as PARTUUID (what the repart
provisioners create) → **legacy**; zero signatures and zero partition
table → **blank**; anything else → **foreign** (ignored, logged, never
written). The manager only ever formats a disk classified blank.

| Disks present  | Action                                                   |
| -------------- | -------------------------------------------------------- |
| LUKS only      | ask passphrase, `cryptsetup open`, boot — steady state    |
| legacy only    | boot unencrypted (lets the config roll out before disks)  |
| legacy + blank | **migrate**, then block with operator instructions        |
| legacy + LUKS  | **block boot** — never run off the unencrypted disk again |
| blank only     | fresh provisioning: servers are born encrypted            |
| none usable    | fail to the emergency target                              |
| duplicates     | block — ambiguous, detach the extra volume                |

Migration: size preflight (target ≥ used + 1 GiB; stale artifacts from an
interrupted attempt are cleaned first) → passphrase asked twice → GPT +
LUKS2 + btrfs → ro snapshot on the source → `btrfs send | receive`
pumped through the daemon (live progress in the TUI) → rw snapshot of
the received subvolume (btrfs-progs 6.x refuses to flip a received one) →
block: "detach the old volume, power-cycle". An interrupted migration
re-blocks safely as legacy+LUKS; recovery is `sgdisk --zap-all` on the
target over initrd SSH and a reboot — the source is never modified.

`/var` mounts by btrfs **filesystem label**, valid whether the fs sits on
a plain partition (pre-migration) or inside the mapper — one fstab entry
for every phase. An initrd-only drop-in orders `sysroot-var.mount` after
(and requires) the manager, so nothing mounts a volume the manager hasn't
approved. `x-systemd.device-timeout=infinity` rides into the main
system's fstab too: a lost device hangs the mount instead of failing —
accepted; passphrase entry must be allowed to take arbitrarily long.

## Operator flow

Every boot blocks in the initrd until the passphrase is entered — an
unattended reboot is an outage until someone unlocks. `ssh -p <port>
root@host` (IPv4 — the initrd only does DHCPv4) lands in the TUI;
Esc/Ctrl-C drops to a shell, `ssh host <cmd>` passes through to
`/bin/sh -c`. The daemon's one-line state is also at
`/run/var-disk-manager/state` for scripting.

To migrate an existing repart-provisioned server: switch the imports
(remove `runtime.repart.var`, add `filesystem.var-luks`, set
`volumeGlob`), deploy **without activating the new fstab on the live
system** (`nixos-rebuild boot` — activation would try to remount the
live `/var` since its device string changes), attach a blank volume at
least as large as the used data, reboot, enter the new passphrase twice,
wait for MIGRATION COMPLETE, detach the old volume, power-cycle, unlock.
Keep the old (cleartext!) volume until the server is verified, then
delete it.

Volume growth is manual with this provisioner (the repart-based online
growth doesn't apply — `hardware/cloud/hetzner.nix` disables its resize
hook via the `varProvisioner` trait): grow the partition, then
`cryptsetup resize <mapper>`, then `btrfs filesystem resize max /var`.

## Traits

`foundrix.traits.filesystem.varProvisioner` (enum: `repart`,
`luks-manager`) announces which module owns `/var` provisioning.
`runtime/repart/var.nix`, `runtime/repart/data.nix` and
`filesystem/var-luks.nix` each announce it, so importing two provisioners
fails eval with a definition conflict on the trait. Hardware modules
consume it to adapt (e.g. Hetzner's repart-driven online-resize hook is
only installed when repart owns the volume).

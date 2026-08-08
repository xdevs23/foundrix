# Backups: `services/backup/`

Snapshot a btrfs subvolume — normally `/var`, the state a deployment cannot
rebuild from its own configuration — and replicate it to whichever backup
destinations are attached. Replication is btrfs send/receive, so every run
after the first carries only the blocks that changed.

The system is split into a source side that knows nothing about destinations,
and destination modules that register themselves with it.

## Pieces

- **`services/backup/btrfs.nix`** — the source side. Mounts the top level of
  the filesystem, declares the btrbk configurations, owns the run and the
  expiry, and derives everything it does with a destination from the
  `destinations` registry. Options live under
  `foundrix.services.backup.btrfs`.
- **`services/backup/smb.nix`** — an SMB/CIFS share as a destination. Options
  live under `foundrix.services.backup.smb`.

Enabling a destination is enough; the source side switches itself on as soon as
one is registered.

```nix
imports = [ foundrixModules.services.backup.smb ];

foundrix.services.backup.smb = {
  enable = true;
  image.size = "500G";
};
```

## Layout

```
/var                     the subvolume being backed up
/varpool                 top level of the same filesystem (subvolid=5)
/varpool/snapshots       snapshots, beside the subvolume they capture
/mnt/backup/smb-share    the CIFS share
/mnt/backup/smb          the btrfs image inside it, loop-mounted
/mnt/backup/smb/btrbk    the backups themselves
```

Three mounts of one filesystem, because a snapshot has to live outside the
subvolume it captures — otherwise the next snapshot captures the previous one
and the nesting compounds — and because send addresses subvolumes by their path
within the filesystem, which needs the top level visible somewhere.
`subvolid=5` is the id of the filesystem root: it always exists and cannot be
renamed out from under the mount.

The SMB destination is a btrfs image file on the share, attached through a loop
device. Send/receive can only write into a btrfs and CIFS is not one, so
without the image every backup would be a full copy.

## How a destination registers

A destination module sets one entry and touches nothing on the source side:

```nix
foundrix.services.backup.btrfs.destinations.<name> = {
  mountPoint = "/mnt/backup/<name>";
  attachOnRun = true;
};
```

From that, the source side derives the targets in the replication config, a
per-destination config for restoring, which mounts a run waits for, and which
destinations to repair before a run starts.

A destination that can be reconfigured while the system is up orders the unit
doing the reconfiguring after `foundrix.services.backup.btrfs.runUnit`, so a
change arriving mid-transfer waits for the run instead of pulling the target
out from under it.

`attachOnRun` is the one judgement call. It is true for a destination that
fails fast when it is absent, such as a network share. It is false for one
whose mount would hold the run for a full device timeout, such as a removable
disk: that destination is backed up when it is already attached, and is
expected to start a run itself when it appears.

## What happens at each stage

**Boot.** The generator runs before any unit is loaded and finds nothing, since
the file it reads lives on tmpfs and the secret it comes from lives on `/var`.
No mount units exist yet. Once the operator's answer is available,
`backup-smb-configure` renders it into `/run/backup-smb/`, and on success
starts `backup-smb-apply`, which reloads systemd — re-running the generator,
which now writes the share mount unit — and on success starts
`backup-smb-mounts.target`, which activates both automounts.

**A changed answer.** `backup-smb-configure.path` sees the secret change and
starts the same chain. `backup-smb-apply` declares `Conflicts=` on the four
mount units, so starting it is what tears the old mounts down.

**A run.** The timer starts `btrbk-backup`, which pulls in the destination
mounts it can cheaply wait for. Before btrbk starts, a root step repairs any
destination that went read-only and creates the snapshot directory and each
destination's target directory. btrbk then takes one snapshot and sends it to
every destination present. Expiry runs afterwards, whether the run succeeded or
not.

**An absent destination.** btrbk reports it as a warning and exits 10, which
the run counts as success. A run that reached the destinations that were there
did its job.

## Restoring

There is a per-destination btrbk configuration for exactly this, because
listing or restoring from one destination has to work while another is
unreachable:

```
btrbk -c /etc/btrbk/backup-smb.conf list all
```

A running system cannot restore its own `/var` — everything is using it, and a
restore overwrites it wholesale. Restoring means booting something that does
not mount `/var`, attaching the pool at its top level, and receiving the chosen
snapshot back into it.

## Decisions, and what was rejected

**A systemd generator writes the one unit that cannot be static.** Which server
and which share are operator facts, and a mount unit cannot take its `What=`
from a variable.

- *Rejected: a run script that mounts the share, sends, and unmounts.* The
  state then lives inside a shell script for the length of a run: systemd
  cannot see what is mounted, a failure part-way leaves mounts behind, and
  nothing of it can be reused for a second kind of destination. Every property
  the units give for free — idle release, ordering, conflict-driven teardown —
  would have to be re-implemented, worse.
- *Rejected: a service that writes unit files into `/run/systemd/system`.*
  Those files survive a daemon reload, so removing a destination means
  remembering to delete them, and a stale definition can outlive the
  configuration that produced it. A generator directory is emptied and rebuilt
  on every reload, which makes staleness impossible by construction.
- *Rejected: a static mount unit plus a drop-in supplying `What=`.* `What=` is
  not additive; a drop-in cannot fill in a value the base unit has to leave
  empty.
- *Rejected: generating all four mount units.* Only the share mount depends on
  an operator fact. The rest are declared as ordinary NixOS units, where they
  are visible in the configuration and reviewable.

**The secret is parsed by systemd, not by a shell.** `backup-smb-configure`
reads it through `EnvironmentFile=` and writes two files: one line for the
generator to paste into the unit, and a credentials file in the form
`mount.cifs` expects, named by the mount options so the password never reaches
a unit file, a process listing or the journal.

- *Rejected: the generator reading the secret itself.* It would have to parse
  env-file syntax in shell, in a context that runs on every daemon reload, and
  the password would pass through a shell for no reason.

**Both mounts are automounts with an idle timeout.** An unreachable server
costs nothing between backups, boot is never held up, and nothing can fill or
corrupt the image while no backup is running.

- *Rejected: mounting only for the duration of a run.* Same property, but
  achieved imperatively and only for the code path that remembers to do it.

**Expiry follows the run instead of having its own timer.** btrbk skips a whole
volume when one of its destinations is unreachable, and skips expiring that
volume's snapshots along with it — so a fortnight of an unreachable share
fills the pool with snapshots nothing will delete. A second configuration
carrying no destinations applies the retention locally, started by
`OnSuccess=`/`OnFailure=` on the run.

- *Rejected: a timer of its own.* It would fire at the same calendar time as
  the run and could delete the parent snapshot an in-flight incremental send is
  working from.

**Reconfiguration is ordered behind a run, not masked out of it.**
`backup-smb-apply` declares `After=` on the run, so a credential change during
a transfer is applied the moment the transfer ends.

- *Rejected: masking the reconfiguration units for the duration of a run.* The
  change is then dropped instead of delayed — the path unit has already fired
  and will not fire again — and a run that dies in a way that skips its cleanup
  leaves the destination unreconfigurable until someone notices.

**A destination is confirmed mounted before anything is written to it.** A
share that failed to mount leaves an ordinary empty directory behind. Without
that check the backup lands on the local disk and the run reports success,
filling the very filesystem it was meant to protect.

**A destination found read-only is detached and attached again.** A btrfs that
hits an I/O error is forced read-only and stays that way: after an aborted
transaction it refuses `remount,rw`, and only a full unmount clears it. Left
alone, one transient error silently kills every backup after it.

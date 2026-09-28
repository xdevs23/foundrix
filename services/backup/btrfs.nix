# Snapshot a btrfs subvolume and replicate it to every backup destination that
# is currently attached.
#
# The subvolume is normally /var: the state a deployment cannot rebuild from
# its own configuration. Replication is btrfs send/receive, so every run after
# the first transfers only the blocks that changed since the previous one.
#
# This is the source side, and it knows nothing about where backups go. A
# destination module — services/backup/smb.nix, and further ones as they are
# written — registers itself under `destinations`, and everything below is
# derived from that registry: the targets written into the replication config,
# the mounts a run waits for, and the destinations to repair before one starts.
# Adding a destination therefore means writing one module and touching nothing
# here.
#
# Three things are less obvious than they look:
#
# Why the filesystem is mounted a second time. Snapshots kept inside a
# subvolume belong to that subvolume. When the subvolume is swapped for a
# restored copy, the copy starts with an empty snapshot directory, and the old
# subvolume cannot be deleted while the snapshots are still inside it.
# `poolMountPoint` is the top level of the same filesystem (subvolid=5, the id
# of the filesystem root, which always exists and never changes), where the
# subvolume and the snapshot directory sit beside each other. Kept there, the
# snapshots outlive a swap of the subvolume, and with them the btrbk history
# and the parent of the next incremental send. The rename that such a swap
# starts with also happens in this directory.
#
# Why an absent destination is not a failure. btrbk signals "finished, with
# warnings" with exit code 10, and an unreachable destination is one of those
# warnings. A run that reached the destinations that were there did its job, so
# 10 counts as success. A destination that is never there is a monitoring
# question, not a reason to fail every run and train an operator to ignore it.
#
# Why expiry is a second unit. btrbk skips a whole volume when one of its
# destinations is unreachable, and skips expiring that volume's snapshots along
# with it. Left at that, a fortnight of an unreachable share fills the pool with
# snapshots that nothing will ever delete. So a second configuration carrying no
# destinations at all exists purely to apply the retention locally. It runs when
# a run finishes, whether that run succeeded or failed, which is both when
# expiry is due and the one moment it cannot collide with a transfer.
{
  config,
  lib,
  pkgs,
  utils,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;

  # The filesystem being backed up. Device and subvolume are read back out of
  # it instead of being restated: a backup pointed at the wrong device or the
  # wrong subvolume silently protects nothing, and a second source of truth is
  # a second thing that can disagree.
  sourceFs = config.fileSystems.${cfg.mountPoint} or null;
  subvolOption = lib.findFirst (lib.hasPrefix "subvol=") null (sourceFs.options or [ ]);

  # Every destination keeps its backups in a subdirectory of the same name, so
  # a destination stays recognisable when it is carried to another machine or
  # inspected by hand.
  targetSubdir = "btrbk";
  targetPath = destination: "${destination.mountPoint}/${targetSubdir}";

  snapshotPath = "${cfg.poolMountPoint}/${cfg.snapshotDir}";

  destinations = lib.attrValues cfg.destinations;

  # Pulled in and waited for by a run. A destination that would make the run
  # sit through a device timeout when it is absent stays out of this list and
  # is picked up only when it is already attached.
  attachedUnits = map (d: d.mountUnit) (lib.filter (d: d.attachOnRun) destinations);

  # The account nixpkgs' btrbk module runs the replication as. It reaches the
  # btrfs commands through a narrow set of sudo rules, so what it needs handed
  # to it directly is ownership of the directories it writes into.
  btrbkUser = "btrbk";

  perDestination =
    render: lib.concatStringsSep "\n" (lib.mapAttrsToList (_: render) cfg.destinations);

  # Runs as root immediately before each replication run.
  prepareRun = pkgs.writeShellApplication {
    name = "backup-prepare-run";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      systemd
    ];
    text = ''
      # A btrfs that hits an I/O error is forced read-only and stays that way:
      # after an aborted transaction it refuses remount,rw, and only a full
      # unmount clears the state. A network destination dropping writes under
      # memory pressure is the usual cause. Left alone, one transient error
      # silently kills every backup after it, so a destination found in that
      # state is detached and attached again here.
      #
      # findmnt answers from the kernel's mount table and never walks the path
      # itself. That matters: touching a path an automount covers triggers that
      # automount, which blocks for the full timeout when the destination is
      # not there.
      recover() {
        local mount_point="$1" unit="$2"
        findmnt --noheadings --types btrfs --options ro "$mount_point" > /dev/null || return 0

        echo "$mount_point went read-only after an earlier I/O error, attaching it again"
        systemctl stop "$unit"
        # It was mounted a moment ago, so the disk or the share is there and
        # there is no reason to wait for the next access to find out.
        systemctl start "$unit" || echo "$mount_point could not be attached again"
      }

      # btrbk writes into a subdirectory of the destination and does not create
      # it. `trigger` says whether reaching for an absent destination is cheap:
      # a network share fails fast, a removable disk would hold the run for the
      # whole device timeout, so that one is prepared only once attached.
      #
      # The mount is confirmed before anything is written. Without that check a
      # share that failed to mount leaves an ordinary empty directory behind,
      # the backup lands on the local disk, and the run reports success while
      # filling the very filesystem it was meant to protect.
      prepare() {
        local mount_point="$1" trigger="$2"
        if [ "$trigger" = yes ]; then
          ls "$mount_point" > /dev/null 2>&1 || true
        fi

        if ! findmnt --noheadings "$mount_point" > /dev/null; then
          echo "$mount_point is not attached, leaving it out of this run"
          return 0
        fi

        # One destination failing here is that destination's problem. Letting
        # it abort the whole step would take every other destination down with
        # it, which is the opposite of what an absent one does two lines up.
        local dir="$mount_point/${targetSubdir}"
        if ! { mkdir -p "$dir" && chown ${btrbkUser}:${btrbkUser} "$dir"; }; then
          echo "$mount_point is attached but $dir could not be prepared, leaving it out of this run"
          return 0
        fi
      }

      # Where snapshots are taken, beside the subvolume they capture. Created
      # here and not by tmpfiles: the pool is a nofail mount, which systemd
      # deliberately does not order before the tmpfiles pass, so the directory
      # could land in the empty mount point underneath and be hidden the moment
      # the pool is attached.
      mkdir -p "${snapshotPath}"
      chown ${btrbkUser}:${btrbkUser} "${snapshotPath}"

      ${perDestination (d: ''recover "${d.mountPoint}" "${d.mountUnit}"'')}

      ${perDestination (d: ''prepare "${d.mountPoint}" "${if d.attachOnRun then "yes" else "no"}"'')}
    '';
  };

  # Shared by every generated replication config. Retention is the same at both
  # ends: the local snapshot is what makes the next send incremental, and the
  # copy on the destination is the backup. `latest` on both minimums keeps the
  # newest of each even once it is past its retention, so there is always a
  # common ancestor to send from and always something to restore.
  commonSettings = {
    timestamp_format = "long";
    snapshot_preserve_min = "latest";
    snapshot_preserve = cfg.retention;
    target_preserve_min = "latest";
    target_preserve = cfg.retention;
    stream_buffer = "256m";
  };

  # Addressed from the pool's top level, where the subvolume and the snapshot
  # directory are siblings.
  settingsFor =
    targets:
    commonSettings
    // {
      volume.${cfg.poolMountPoint} = {
        snapshot_dir = cfg.snapshotDir;
        subvolume.${cfg.subvolume} = lib.optionalAttrs (targets != [ ]) {
          target = lib.genAttrs targets (_: { });
        };
      };
    };

  # One config per destination, carrying no timer. They exist for the operator:
  # listing or restoring from one destination has to work while another is
  # unreachable, which a config naming both cannot do.
  perDestinationInstances = lib.mapAttrs' (
    name: destination:
    lib.nameValuePair "backup-${name}" {
      onCalendar = null;
      settings = settingsFor [ (targetPath destination) ];
    }
  ) cfg.destinations;

  # nixpkgs generates a service for every instance. The per-destination configs
  # are meant to be used by hand, so their services are turned off instead of
  # sitting there as a second way to start a backup that does something subtly
  # different from the real one.
  perDestinationServices =
    lib.genAttrs (map (name: "btrbk-${name}") (lib.attrNames perDestinationInstances))
      (_: {
        enable = false;
      });

  destinationType = lib.types.submodule (destination: {
    options = {
      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/backup/${destination.name}";
        defaultText = lib.literalExpression ''"/mnt/backup/''${name}"'';
        description = ''
          Where the destination's btrfs is mounted. Backups are written into a
          `${targetSubdir}` subdirectory of it.
        '';
      };

      mountUnit = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = utils.escapeSystemdPath destination.config.mountPoint + ".mount";
        defaultText = lib.literalMD "the mount unit systemd derives from `mountPoint`";
        description = "Mount unit for `mountPoint`, as the run refers to it.";
      };

      attachOnRun = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether a run pulls this destination's mount in and waits for it.

          True for a destination that fails fast when it is not there, such as
          a network share. False for one whose mount waits out a device
          timeout, such as a removable disk — that destination is backed up
          when it is already attached, and is expected to trigger a run itself
          when it appears.
        '';
      };

    };
  });
in
{
  options = namespaced __curPos {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.destinations != { };
      defaultText = lib.literalMD "true once a destination module has registered one";
      description = ''
        Whether to snapshot `mountPoint` and replicate it. On by default as
        soon as a destination exists, since a source with nowhere to send to
        and a destination nothing sends to are both useless on their own.
      '';
    };

    destinations = lib.mkOption {
      type = lib.types.attrsOf destinationType;
      default = { };
      description = ''
        Backup destinations. Destination modules register themselves here; it
        is not meant to be written out by hand. Everything a run does with a
        destination is derived from this.
      '';
    };

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/var";
      description = ''
        Mount point of the btrfs subvolume to back up. Its device and its
        subvolume name are read out of this filesystem's own definition, so
        there is nothing else to keep in step with it.
      '';
    };

    poolMountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/varpool";
      description = ''
        Where to mount the top level of the btrfs that holds `mountPoint`.
        Snapshots are taken there, beside the subvolume, so they outlive a
        swap of the subvolume for a restored copy. Snapshots inside the
        subvolume would stay behind in the old one.
      '';
    };

    snapshotDir = lib.mkOption {
      type = lib.types.str;
      default = "snapshots";
      description = "Directory within the pool that snapshots are taken into.";
    };

    device = lib.mkOption {
      type = lib.types.str;
      default = sourceFs.device or "";
      defaultText = lib.literalExpression "config.fileSystems.<mountPoint>.device";
      description = "Block device holding the btrfs. Defaults to the one `mountPoint` is on.";
    };

    subvolume = lib.mkOption {
      type = lib.types.str;
      default = if subvolOption != null then lib.removePrefix "subvol=" subvolOption else "";
      defaultText = lib.literalExpression "the `subvol=` mount option of `mountPoint`";
      description = "Name of the subvolume within the pool, as btrbk addresses it.";
    };

    retention = lib.mkOption {
      type = lib.types.str;
      default = "7d";
      description = ''
        How long to keep snapshots, locally and on every destination, in
        btrbk's retention syntax.
      '';
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "When to run, in systemd calendar format.";
    };

    timeout = lib.mkOption {
      type = lib.types.str;
      default = "6h";
      description = ''
        How long a single run may take before it is killed. The bound that
        matters is the first transfer, which carries the whole subvolume over
        whatever link the destination is on; later runs carry a day of changes.
      '';
    };

    runUnit = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "btrbk-backup.service";
      description = ''
        Unit that performs a run. A destination that can be reconfigured while
        the system is up orders the unit doing the reconfiguring after this
        one, so a change arriving mid-transfer waits instead of pulling the
        target out from under an in-flight send.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.device != "";
        message = ''
          foundrix.services.backup.btrfs: no device for ${cfg.mountPoint}. It is
          not a filesystem this configuration declares, so set `device`
          explicitly.
        '';
      }
      {
        assertion = cfg.subvolume != "";
        message = ''
          foundrix.services.backup.btrfs: ${cfg.mountPoint} has no `subvol=`
          mount option to take the subvolume name from. Set `subvolume`
          explicitly, or point `mountPoint` at a btrfs subvolume.
        '';
      }
      {
        assertion = cfg.destinations != { };
        message = ''
          foundrix.services.backup.btrfs is enabled but no destination is
          registered, so every run would snapshot and send nowhere. Enable a
          destination module, such as foundrix.services.backup.smb.
        '';
      }
    ];

    # The top level of the filesystem, so snapshots sit beside the subvolume
    # instead of inside it. nofail: this mount exists for backups, and its
    # absence must never keep the machine from booting.
    fileSystems.${cfg.poolMountPoint} = {
      inherit (cfg) device;
      fsType = "btrfs";
      options = [
        "subvolid=5"
        "noatime"
        "nofail"
      ];
    };

    # Mount points and their parents. A backup holds everything the system
    # holds, so nothing below is readable by anyone but root.
    systemd.tmpfiles.settings.backup =
      lib.genAttrs
        (lib.unique (
          lib.concatMap (d: [
            (builtins.dirOf d.mountPoint)
            d.mountPoint
          ]) destinations
        ))
        (_: {
          d = {
            mode = "0750";
            user = "root";
            group = "root";
          };
        });

    services.btrbk.instances = perDestinationInstances // {
      # The scheduled run: one snapshot per run, sent to every destination.
      backup = {
        onCalendar = cfg.onCalendar;
        settings = settingsFor (map targetPath destinations);
      };

      # Expiry only. See the header for why it cannot share a config with the
      # run above.
      backup-prune = {
        onCalendar = null;
        settings = settingsFor [ ];
      };
    };

    systemd.services = perDestinationServices // {
      btrbk-backup = {
        # Says which of several btrbk units this one is, which the generic
        # upstream description does not.
        description = lib.mkForce "Snapshot ${cfg.mountPoint} and replicate it to every attached backup destination";
        wants = attachedUnits;
        after = attachedUnits;
        unitConfig = {
          RequiresMountsFor = [ cfg.poolMountPoint ];
          # Expiry follows every run, however it ended. See the header for why
          # it cannot be part of the run itself, and why a timer of its own
          # would be a race against the transfer.
          OnSuccess = "btrbk-backup-prune.service";
          OnFailure = "btrbk-backup-prune.service";
        };
        serviceConfig = {
          # "+" runs the step as root: the replication itself is unprivileged,
          # while detaching a mount and handing over a directory are not.
          ExecStartPre = [ "+${lib.getExe prepareRun}" ];
          # See the header: warnings, an unreachable destination among them,
          # are a complete run and not a failure.
          SuccessExitStatus = [ 10 ];
          TimeoutStartSec = cfg.timeout;
        };
      };

      # The service nixpkgs generates for the expiry instance, kept and pointed
      # at `prune`: everything else about it — the account, the scheduling
      # class, the state directory — is already what this needs.
      btrbk-backup-prune = {
        description = lib.mkForce "Expire backup snapshots that are past their retention";
        unitConfig.RequiresMountsFor = [ cfg.poolMountPoint ];
        serviceConfig = {
          ExecStart = lib.mkForce "${pkgs.btrbk}/bin/btrbk -c /etc/btrbk/backup-prune.conf prune";
          SuccessExitStatus = [ 10 ];
        };
      };
    };

    # Spread across the hour: several machines backing up to the same server at
    # exactly midnight is a self-inflicted thundering herd.
    systemd.timers.btrbk-backup.timerConfig.RandomizedDelaySec = "30m";
  };
}

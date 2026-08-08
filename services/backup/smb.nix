# An SMB/CIFS share as a backup destination.
#
# Why a filesystem image is involved. Replication is btrfs send/receive, which
# can only write into a btrfs, and CIFS is not one. So the share holds a single
# large file formatted as btrfs, that file is attached through a loop device,
# and the result is a real btrfs living on a network share. Snapshots can then
# be sent into it incrementally, which is what makes a nightly backup over a
# slow link affordable at all.
#
# That gives two mounts, stacked:
#
#   /mnt/backup/smb-share   the CIFS share itself
#   /mnt/backup/smb         the btrfs image inside it, loop-mounted — the
#                           destination the source side knows about
#
# Both are automounts. The share is attached on first access and released once
# idle, so an unreachable server costs nothing between backups, never holds up
# a boot, and nothing can fill or corrupt the image while no backup is running.
#
# Why one unit is generated at runtime. Which server and which share are
# operator facts, not deployment ones: they are collected once at first boot
# and cannot be known when the system is built. A mount unit cannot take its
# `What=` from a variable, so that single unit is written by a systemd
# generator, which runs at boot and again on every daemon reload. Everything
# else about this destination is static and is declared here as ordinary units.
#
# Generators are what makes this self-correcting: the generator directory is
# emptied and rebuilt on each reload, so a changed share replaces the old unit
# and a removed configuration leaves nothing behind. There is no state to clean
# up and no way for a stale mount definition to survive.
#
# Why applying a change takes two steps. A unit cannot start units it declares
# `Conflicts=` with. The apply service needs that conflict, because starting it
# is what tears the running mounts down; the mounts are then brought back up by
# a target it activates on success.
{
  config,
  lib,
  pkgs,
  utils,
  foundrixModules,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;

  shareMountPoint = "/mnt/backup/smb-share";
  imageMountPoint = "/mnt/backup/smb";

  shareMountUnit = utils.escapeSystemdPath shareMountPoint + ".mount";
  shareAutomountUnit = utils.escapeSystemdPath shareMountPoint + ".automount";
  imageMountUnit = utils.escapeSystemdPath imageMountPoint + ".mount";
  imageAutomountUnit = utils.escapeSystemdPath imageMountPoint + ".automount";

  mountsTarget = "backup-smb-mounts.target";

  # Written by the configure service below, read by the generator and by
  # mount.cifs. On tmpfs, so a reboot starts from nothing and the operator's
  # answer is rendered again from the one durable copy.
  runtimeDir = "/run/backup-smb";
  targetFile = "${runtimeDir}/target";
  credentialsFile = "${runtimeDir}/credentials";

  # Where the image is attached for a resize. Deliberately not its own mount
  # point, which stays uncovered until the size is settled and the mount unit
  # brings it up for real.
  resizeDir = "/run/backup-smb-resize";

  imageFile = "${shareMountPoint}/${cfg.image.name}";

  # The one durable file this destination is configured from. Read back out of
  # the secret instead of being restated, so its location is defined once.
  credentialsEnv = config.foundrix.services.operator-secrets.secrets.backup-smb.path;

  systemctl = lib.getExe' pkgs.systemd "systemctl";

  # Renders the operator's answer into the two files the mounts need. systemd
  # reads the secret through `EnvironmentFile=` and hands the values over as
  # environment variables, so nothing here has to parse the file's syntax and
  # the values cannot be mangled on the way through a shell.
  configureDestination = pkgs.writeShellApplication {
    name = "backup-smb-configure";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # Named after the secret's fields, and reachable here only because
      # systemd put them in the environment. Each one is required: a secret
      # missing a field means the collector accepted something incomplete, and
      # a mount unit built from it would fail in a far less obvious way.
      server="''${server:?the backup-smb secret carries no server}"
      share="''${share:?the backup-smb secret carries no share}"
      username="''${username:?the backup-smb secret carries no username}"
      password="''${password:?the backup-smb secret carries no password}"

      # What the generator pastes into the mount unit, on one line, so the
      # generator needs no parser of its own.
      printf '//%s/%s\n' "$server" "$share" > ${targetFile}

      # The form mount.cifs expects. The mount options name this file, so the
      # password never appears in a unit file, in a process listing or in the
      # journal.
      printf 'username=%s\npassword=%s\n' "$username" "$password" > ${credentialsFile}
    '';
  };

  # Writes the one unit whose contents cannot be known at build time. systemd
  # runs it at boot and on every daemon reload, passing the directory for
  # normal units as the first argument.
  generateShareMount = pkgs.writeShellApplication {
    name = "backup-smb-generator";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      normal_dir="''${1:?systemd passes the normal-unit directory as the first argument}"

      # Nothing to generate until the operator's answer has been rendered. That
      # is the normal state early in a boot: this runs long before the
      # filesystem holding the secret is mounted, and again once it has been.
      [ -r "${targetFile}" ] || exit 0
      target="$(cat "${targetFile}")"
      [ -n "$target" ] || exit 0

      cat > "$normal_dir/${shareMountUnit}" <<EOF
      [Unit]
      Description=SMB share holding the backup filesystem image
      Requires=${shareAutomountUnit}
      After=${shareAutomountUnit} network-online.target
      # A failed mount is retried on the next access. Without this it would be
      # rate-limited into permanent failure that only a reboot clears.
      StartLimitIntervalSec=5
      StartLimitBurst=0

      [Mount]
      What=$target
      Where=${shareMountPoint}
      Type=cifs
      # soft: a server that stops answering makes operations fail instead of
      # hanging for good, which is also what keeps the unmount from hanging.
      # The share holds one file, readable by root alone.
      Options=credentials=${credentialsFile},_netdev,soft,echo_interval=10,actimeo=30,uid=0,gid=0,file_mode=0600,dir_mode=0700
      TimeoutSec=30
      EOF
    '';
  };

  # Creates the image on first use and matches it to the configured size on
  # every later run, so the size stays a declared fact and not something an
  # operator has to remember to change in two places.
  prepareImage = pkgs.writeShellApplication {
    name = "backup-smb-image";
    runtimeInputs = with pkgs; [
      coreutils
      btrfs-progs
      util-linux
    ];
    text = ''
      target_bytes=$(numfmt --from=iec "${cfg.image.size}")

      # Reaching into the share is what triggers its automount.
      if [ ! -w "${shareMountPoint}" ]; then
        echo "${shareMountPoint} is not writable; check the credentials and the server-side permissions" >&2
        exit 1
      fi

      # Fail loudly instead of letting the loop device be attached read-only:
      # replication would give up on the destination, the run would still
      # report success, and the backup would look healthy while storing nothing.
      if [ -e "${imageFile}" ] && [ ! -w "${imageFile}" ]; then
        echo "${imageFile} exists but is not writable; refusing to attach it read-only" >&2
        exit 1
      fi

      free_bytes=$(df --output=avail --block-size=1 "${shareMountPoint}" | tail -1)

      if [ ! -f "${imageFile}" ]; then
        if [ "$target_bytes" -gt "$free_bytes" ]; then
          echo "not enough room on the share for a ${cfg.image.size} image ($free_bytes bytes free)" >&2
          exit 1
        fi
        echo "Creating a ${cfg.image.size} filesystem image at ${imageFile}"
        # Sparse: the file reads as its full size but occupies only what has
        # been written, which is what matters on a share billed by usage.
        truncate -s "$target_bytes" "${imageFile}"
        mkfs.btrfs -L backup-smb "${imageFile}"
        exit 0
      fi

      current_bytes=$(stat -c %s "${imageFile}")
      if [ "$current_bytes" -eq "$target_bytes" ]; then
        exit 0
      fi

      mkdir -p ${resizeDir}
      trap 'umount ${resizeDir} 2> /dev/null || true' EXIT

      if [ "$target_bytes" -gt "$current_bytes" ]; then
        if [ "$((target_bytes - current_bytes))" -gt "$free_bytes" ]; then
          echo "cannot grow the image to ${cfg.image.size}, the share has only $free_bytes bytes free; keeping the current size" >&2
          exit 0
        fi
        # Growing: extend the file first, then let the filesystem claim the new
        # space. It has to be mounted for that, so it is attached out of the way.
        echo "Growing the image from $current_bytes to $target_bytes bytes"
        truncate -s "$target_bytes" "${imageFile}"
        mount "${imageFile}" ${resizeDir}
        btrfs filesystem resize max ${resizeDir}
        umount ${resizeDir}
      else
        # Shrinking is the reverse order: the filesystem gives the space back
        # before the file may be truncated, or the truncation cuts off blocks
        # the filesystem still believes it owns.
        echo "Shrinking the image from $current_bytes to $target_bytes bytes"
        mount "${imageFile}" ${resizeDir}
        if btrfs filesystem resize "$target_bytes" ${resizeDir}; then
          umount ${resizeDir}
          truncate -s "$target_bytes" "${imageFile}"
        else
          # btrfs refuses to shrink below what its data occupies.
          echo "cannot shrink the filesystem, not enough free space inside it; keeping the current size" >&2
          umount ${resizeDir}
        fi
      fi
    '';
  };

  # Proving the credentials at collection time is worth the round trip:
  # accepting them on presence alone takes a mistyped password happily, and the
  # operator finds out at the first unattended run, days later, with nothing
  # backed up in between.
  credentialsValidator = pkgs.writeShellApplication {
    name = "backup-smb-validate";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      samba
    ];
    text = ''
      fields=$(jq -r '.fields | .server, .share, .username, .password' 2> /dev/null) || {
        echo '{"status":"error"}'
        exit 0
      }
      mapfile -t values <<< "$fields"
      server="''${values[0]-}"
      share="''${values[1]-}"
      username="''${values[2]-}"
      password="''${values[3]-}"

      if [ -z "$server" ] || [ -z "$share" ] || [ -z "$username" ] || [ -z "$password" ]; then
        echo '{"status":"invalid"}'
        exit 0
      fi

      # A directory listing proves the whole chain at once: the host resolves,
      # the share exists, and the credentials open it. It never touches data.
      if output=$(PASSWD="$password" smbclient "//$server/$share" -U "$username" -c 'ls' 2>&1); then
        echo '{"status":"valid"}'
      elif grep -qiE 'logon failure|access denied|bad password|no such share|not found' <<< "$output"; then
        echo '{"status":"invalid"}'
      else
        # An unreachable server, DNS not up yet, a network still settling: none
        # of that is proof the credentials are wrong, and `error` never
        # discards what is already stored.
        echo '{"status":"error"}'
      fi
    '';
  };
in
{
  imports = [
    foundrixModules.services.backup.btrfs
    foundrixModules.services.operator-secrets
    foundrixModules.services.nftables-dns
  ];

  options = namespaced __curPos {
    enable = lib.mkEnableOption "an SMB share as a backup destination";

    image = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "backup.img";
        description = "Name of the filesystem image file on the share.";
      };

      size = lib.mkOption {
        type = lib.types.str;
        default = "200G";
        description = ''
          Size of the filesystem image, in IEC units. Sparse, so this is a
          ceiling and not an allocation, but it cannot exceed what the share
          allows. Changing it later resizes the filesystem inside the image as
          well, on the next run.
        '';
      };
    };

    idleTimeout = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = ''
        How long the mounts may sit unused before they are released. Short
        enough that the share is absent between backups, long enough that a
        pause inside one run does not tear it down mid-transfer.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Caught here and not at the first run: a size the image service cannot
    # parse leaves the destination silently absent, which every run then
    # reports as nothing worse than a warning.
    assertions = [
      {
        assertion = builtins.match "[0-9]+[KMGTP]?" cfg.image.size != null;
        message = ''
          foundrix.services.backup.smb.image.size is "${cfg.image.size}", which
          is not a number with an optional IEC suffix (for example "200G").
        '';
      }
    ];

    boot.supportedFilesystems.cifs = true;

    # The source side needs to know nothing beyond this: where the destination
    # is, and that reaching for it is cheap when it is absent.
    foundrix.services.backup.btrfs.destinations.smb = {
      mountPoint = imageMountPoint;
      attachOnRun = true;
    };

    # Where the share is and how to log into it is an operator fact, collected
    # once at first boot. Nothing about it is known to this configuration.
    foundrix.services.operator-secrets.secrets.backup-smb = {
      description = "SMB share and credentials for off-site backups";
      fields = {
        server = {
          order = 10;
          description = "Hostname of the SMB server";
        };
        share = {
          order = 20;
          description = "Share name on that server";
        };
        username.order = 30;
        password = {
          order = 40;
          sensitive = true;
        };
      };
      validateCommand = [ (lib.getExe credentialsValidator) ];
      # Gives the configure service Requires= and After= on the collector, so
      # it cannot run before the answer exists.
      requiredBy = [ "backup-smb-configure.service" ];
    };

    # An egress firewall only lets listed destinations out, and the server is
    # an operator fact this configuration never learns — so the allowance is by
    # port and not by host.
    foundrix.services.nftables-dns.allowedConnections = [
      {
        host = "*";
        ports = [ 445 ];
      }
    ];

    # The share's mount point. The destination's own mount point is created by
    # the source side, which owns the mount points of everything it writes to.
    systemd.tmpfiles.settings.backup-smb.${shareMountPoint}.d = {
      mode = "0750";
      user = "root";
      group = "root";
    };

    systemd.generators.backup-smb = lib.getExe generateShareMount;

    systemd.services.backup-smb-configure = {
      description = "Render the SMB backup destination from the operator's answer";
      wantedBy = [ "multi-user.target" ];
      unitConfig = {
        ConditionPathExists = credentialsEnv;
        # Deliberately not RemainAfterExit: the path unit below can only start
        # this again once it has gone inactive.
        OnSuccess = "backup-smb-apply.service";
      };
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = credentialsEnv;
        RuntimeDirectory = lib.removePrefix "/run/" runtimeDir;
        RuntimeDirectoryMode = "0700";
        # The rendered files outlive the service that wrote them; the generator
        # reads one of them on every daemon reload.
        RuntimeDirectoryPreserve = "yes";
        UMask = "0077";
        ExecStart = lib.getExe configureDestination;
      };
    };

    # A changed answer takes effect without a reboot.
    systemd.paths.backup-smb-configure = {
      description = "Watch the SMB backup credentials for changes";
      wantedBy = [ "multi-user.target" ];
      unitConfig.StartLimitIntervalSec = 0;
      pathConfig.PathChanged = credentialsEnv;
    };

    # Conflicts= is what performs the teardown, After= waits for it to finish.
    # This must not stay active afterwards, or the conflict would still stand
    # when the mounts are started again.
    systemd.services.backup-smb-apply = {
      description = "Apply the SMB backup destination configuration";
      conflicts = [
        imageAutomountUnit
        imageMountUnit
        shareAutomountUnit
        shareMountUnit
      ];
      after = [
        imageAutomountUnit
        imageMountUnit
        shareAutomountUnit
        shareMountUnit
        # A backup in progress is holding the mounts this tears down, so a
        # change arriving mid-transfer queues behind the run instead of
        # cutting it off. Ordering and not masking, so the change is applied
        # when the run ends instead of being dropped.
        config.foundrix.services.backup.btrfs.runUnit
      ];
      unitConfig.StartLimitIntervalSec = 0;
      # Separate from the teardown because a unit cannot start what it
      # conflicts with.
      unitConfig.OnSuccess = mountsTarget;
      serviceConfig = {
        Type = "oneshot";
        # Re-runs every generator, which is what picks up the rewritten
        # configuration and drops units the configuration no longer describes.
        ExecStart = "${systemctl} daemon-reload";
      };
    };

    systemd.targets.backup-smb-mounts = {
      description = "SMB backup share and filesystem image";
    };

    # Pulled in by the image mount below, so it always runs before the image is
    # attached, and after the share it lives on.
    systemd.services.backup-smb-image = {
      description = "Create or resize the SMB backup filesystem image";
      requires = [ shareAutomountUnit ];
      after = [ shareAutomountUnit ];
      unitConfig.ConditionPathExists = targetFile;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe prepareImage;
      };
    };

    # Static: only the share mount's `What=` depends on the operator's answer,
    # so only that one unit is generated.
    systemd.mounts = [
      {
        description = "Backup filesystem image on the SMB share";
        what = imageFile;
        where = imageMountPoint;
        type = "btrfs";
        options = "compress=zstd,noatime";
        requires = [
          imageAutomountUnit
          "backup-smb-image.service"
        ];
        after = [
          imageAutomountUnit
          "backup-smb-image.service"
        ];
        # Started by its automount, by the backup run, or by hand — never
        # simply because the system booted.
        wantedBy = [ ];
      }
    ];

    # Attached on first access and released once idle, so an unreachable server
    # costs nothing between backups. Both are started by the target above,
    # which the apply service activates once the units are in place.
    systemd.automounts = [
      {
        description = "SMB share holding the backup filesystem image";
        where = shareMountPoint;
        wantedBy = [ mountsTarget ];
        automountConfig = {
          TimeoutIdleSec = cfg.idleTimeout;
          DirectoryMode = "0750";
        };
      }
      {
        description = "Backup filesystem image on the SMB share";
        where = imageMountPoint;
        requires = [ shareAutomountUnit ];
        after = [ shareAutomountUnit ];
        wantedBy = [ mountsTarget ];
        automountConfig = {
          TimeoutIdleSec = cfg.idleTimeout;
          DirectoryMode = "0750";
        };
      }
    ];
  };
}

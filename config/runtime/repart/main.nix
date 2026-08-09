# Grow the image-built main partition to fill its disk.
#
# An image is built at minimal size: the main partition holds exactly the
# closure it was born with. Deployed to a real disk, everything beyond that
# stays unpartitioned — the store fills up while most of the disk sits
# unused, and nothing in the running system ever claims it.
#
# The online-resize path in hardware/cloud/hetzner.nix does not cover this:
# it reacts to a disk-changed event, which only fires when a provider
# enlarges a volume at runtime. A disk that was always bigger than the image
# never emits one. Growth to the disk's existing size therefore has to
# happen at boot, unconditionally and idempotently: once grown, later boots
# find nothing to do.
#
# One definition, for the main partition only. systemd-repart leaves
# existing partitions without a definition untouched, so the ESP needs no
# entry — and with a single definition carrying the only weight, all free
# space goes to the main partition. Relocating the backup GPT header to the
# real end of the disk is part of what repart does on the way.
{
  config,
  lib,
  namespaced,
  namespacedCfg,
  foundrixModules,
  ...
}:
{
  imports = [ foundrixModules.config.repart-config ];

  options = namespaced __curPos {
    disk = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/sda";
      description = ''
        Disk holding the image-built main partition. When set, a boot-time
        systemd-repart grows that partition — and the btrfs inside it — to
        fill the disk.
      '';
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    lib.mkIf (cfg.disk != null) {
      assertions = [
        {
          assertion = (config.foundrix.traits.filesystem.readOnlyStore or null) != true;
          message = ''
            foundrix.config.runtime.repart.main grows the btrfs-writable main
            partition; a read-only (A/B) store layout has no such partition
            and must not enable it.
          '';
        }
      ];

      # The btrfs is grown through the mounted filesystem. /nix is
      # neededForBoot, so by the time this device-bound boot service runs,
      # the mount exists.
      systemd.repartConfig.main-disk = {
        device = cfg.disk;
        partitions."20-main" = {
          Type = "linux-generic";
          Label = "main";
          Format = "btrfs";
          GrowFileSystem = "on";
        };
      };

      # GrowFileSystem= is not acted on when the filesystem is already
      # mounted — repart grows the partition and stops there, silently.
      # Growing a mounted filesystem is systemd-growfs's job, so run it
      # afterwards: the same step the online-resize hook performs after its
      # repart run. Idempotent like the rest — a filesystem already at
      # partition size is a no-op.
      systemd.services."systemd-repart@main-disk".serviceConfig.ExecStartPost = "${config.systemd.package}/bin/systemctl restart systemd-growfs@nix.service";
    };
}

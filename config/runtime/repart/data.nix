# Runtime data partition for HTPC/appliance systems.
#
# Creates a btrfs data partition on first boot for persistent storage.
# Mounted at /var for system state, logs, and application data.
{
  config,
  lib,
  utils,
  namespaced,
  namespacedCfg,
  foundrixModules,
  traitTypes,
  ...
}:
let
  deviceCfg = config.foundrix.config.image.device;
  # Custom partition type GUID for userdata
  dataTypeGuid = "00000000-0000-4000-9000-000000000070";
in
{
  imports = [
    foundrixModules.config.image.device
    foundrixModules.config.filesystem.var
  ];

  options = namespaced __curPos {
    uuid = lib.mkOption {
      type = lib.types.str;
      default = "00000000-0000-4000-9000-100000000070";
      description = "UUID for the data partition";
    };

    format = lib.mkOption {
      type = lib.types.str;
      default = "btrfs";
      description = "Filesystem format for data partition";
    };

    label = lib.mkOption {
      type = lib.types.str;
      default = "userdata";
      description = "Label for the data partition";
    };

    sizeMin = lib.mkOption {
      type = lib.types.str;
      default = "1G";
      description = "Minimum size for data partition";
    };

    sizeMax = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "16G";
      description = "Maximum size for data partition (null for unlimited)";
    };

    priority = lib.mkOption {
      type = lib.types.int;
      default = -15;
      description = "Partition priority (negative = lower priority for space allocation)";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      dataBlkDevPath = "/dev/disk/by-partuuid/${lib.toLower cfg.uuid}";
      dataBlkDevUnit = "${utils.escapeSystemdPath dataBlkDevPath}.device";
    in
    {
      # Announce ownership of /var provisioning; a second provisioner
      # (e.g. filesystem.var-luks) conflicts at eval by enum construction.
      foundrix.traits.filesystem.varProvisioner = traitTypes.filesystem.varProvisioner.repart;

      assertions = [
        {
          assertion = deviceCfg.dataDevice != null;
          message = ''
            foundrix.config.image.device.dataDevice must be set for runtime partitioning.
            Set it to the device path where data partition should be created, e.g.:
              foundrix.config.image.device.dataDevice = "/dev/nvme0n1";
          '';
        }
      ];

      # Enable systemd in initrd (required for repart)
      boot.initrd.systemd.enable = true;

      # Configure initrd repart
      boot.initrd.systemd.repart = {
        enable = true;
        device = deviceCfg.dataDevice;
        empty = "allow";
      };

      # Run repart early without dependencies
      boot.initrd.systemd.services.systemd-repart.after = lib.mkForce [ ];

      # Define the data partition
      systemd.repart = {
        enable = true;
        partitions."21-data" = {
          Type = lib.toLower dataTypeGuid;
          UUID = lib.toLower cfg.uuid;
          Format = cfg.format;
          Label = cfg.label;
          Minimize = "off";
          Encrypt = "off";
          SizeMinBytes = cfg.sizeMin;
          SizeMaxBytes = lib.mkIf (cfg.sizeMax != null) cfg.sizeMax;
          SplitName = "-";
          FactoryReset = "yes";
          Priority = cfg.priority;
        };
      };

      # Default /var filesystem config pointing to the runtime partition
      foundrix.config.filesystem.var = {
        device = lib.mkDefault dataBlkDevPath;
        fsOptions = lib.mkDefault [
          "x-systemd.rw-only"
          "x-systemd.device-timeout=30s"
        ];
      };

      fileSystems."/var".neededForBoot = lib.mkDefault true;

      # Btrfs-specific kernel params
      boot.kernelParams = lib.mkIf (cfg.format == "btrfs") [
        "systemd.setenv=SYSTEMD_REPART_MKFS_OPTIONS_BTRFS=--nodiscard"
      ];

      boot.initrd.supportedFilesystems.btrfs = lib.mkIf (cfg.format == "btrfs") true;
    };
}

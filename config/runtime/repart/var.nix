{
  config,
  lib,
  utils,
  namespaced,
  namespacedCfg,
  foundrixModules,
  ...
}:
let
  deviceCfg = config.foundrix.config.image.device;
in
{
  imports = [
    foundrixModules.config.image.device
    foundrixModules.config.filesystem.var
  ];

  options = namespaced __curPos {
    uuid = lib.mkOption {
      type = lib.types.str;
      default = "4d21b016-b534-45c2-a9fb-5c16e091fd2d";
      description = "UUID for the /var partition";
    };

    format = lib.mkOption {
      type = lib.types.str;
      default = "btrfs";
      description = "Filesystem format for /var partition";
    };

    subvolumes = lib.mkOption {
      type = lib.types.str;
      default = "/var";
      description = "Subvolumes to create (btrfs only)";
    };

    sizeMin = lib.mkOption {
      type = lib.types.str;
      default = "1G";
      description = "Minimum size for /var partition";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      varBlkDevPath = "/dev/disk/by-partuuid/${cfg.uuid}";
      varBlkDevUnit = "${utils.escapeSystemdPath varBlkDevPath}.device";
    in
    {
      assertions = [
        {
          assertion = deviceCfg.dataDevice != null;
          message = ''
            foundrix.config.image.device.dataDevice must be set for runtime partitioning.
            Set it to the device path where /var should be created, e.g.:
              foundrix.config.image.device.dataDevice = "/dev/sdb";
          '';
        }
      ];

      # Enable systemd in initrd (required for repart)
      boot.initrd.systemd.enable = true;

      # Configure initrd repart
      boot.initrd.systemd.repart = {
        enable = true;
        device = deviceCfg.dataDevice;
        empty = "allow"; # Create GPT on empty disk
      };

      # Define the /var partition
      systemd.repart = {
        enable = true;
        partitions."50-var" = {
          Type = "var";
          Format = cfg.format;
          Label = "var";
          UUID = cfg.uuid;
          Subvolumes = lib.mkIf (cfg.format == "btrfs") cfg.subvolumes;
          MakeDirectories = lib.mkIf (cfg.format == "btrfs") cfg.subvolumes;
          SizeMinBytes = cfg.sizeMin;
          FactoryReset = true;
        };
      };

      # Default /var filesystem config pointing to the runtime partition
      foundrix.config.filesystem.var = {
        device = lib.mkDefault varBlkDevPath;
        fsOptions = lib.mkDefault (
          (lib.optionals (cfg.format == "btrfs") [ "subvol=var" ])
          ++ [
            "x-systemd.device-timeout=300s"
            "x-systemd.after=systemd-repart.service"
            "x-systemd.after=${varBlkDevUnit}"
            "x-systemd.requires=systemd-repart.service"
          ]
        );
      };

      # systemd-tmpfiles-setup needs /var to be mounted
      systemd.services.systemd-tmpfiles-setup = {
        requires = [ "var.mount" ];
        after = [ "var.mount" ];
      };

      # Btrfs-specific kernel params
      boot.kernelParams = lib.mkIf (cfg.format == "btrfs") [
        "systemd.setenv=SYSTEMD_REPART_MKFS_OPTIONS_BTRFS=--nodiscard"
      ];
    };
}

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
      repartEnabled = config.boot.initrd.systemd.repart.enable;
    in
    {
      # Announce ownership of /var provisioning; a second provisioner
      # (e.g. filesystem.var-luks) conflicts at eval by enum construction.
      foundrix.traits.filesystem.varProvisioner = traitTypes.filesystem.varProvisioner.repart;

      # Partitioning is handled entirely in the initrd — the main-system
      # systemd-repart.service is not needed and fails to discover the root
      # block device / machine-id when running on a volatile root.
      systemd.repart.enable = lib.mkDefault false;
      boot.initrd.systemd.repart.enable = lib.mkDefault true;

      assertions = lib.mkIf repartEnabled [
        {
          assertion = deviceCfg.dataDevice != null;
          message = ''
            foundrix.config.image.device.dataDevice must be set for runtime partitioning.
            Set it to the device path where /var should be created, e.g.:
              foundrix.config.image.device.dataDevice = "/dev/sdb";
          '';
        }
      ];

      boot.initrd.systemd.enable = lib.mkIf (
        repartEnabled && !lib.versionAtLeast lib.version "26.10"
      ) true;
      boot.initrd.systemd.repart.device = lib.mkIf repartEnabled deviceCfg.dataDevice;
      boot.initrd.systemd.repart.empty = lib.mkIf repartEnabled "allow";

      systemd.repart.partitions = lib.mkIf repartEnabled {
        "50-var" = {
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

      foundrix.config.filesystem.var = lib.mkIf repartEnabled {
        device = lib.mkDefault varBlkDevPath;
        fsOptions = lib.mkDefault (
          (lib.optionals (cfg.format == "btrfs") [ "subvol=var" ])
          ++ [
            "x-systemd.device-timeout=300s"
            "x-systemd.after=${varBlkDevUnit}"
          ]
        );
      };

      boot.kernelParams = lib.mkIf (repartEnabled && cfg.format == "btrfs") [
        "systemd.setenv=SYSTEMD_REPART_MKFS_OPTIONS_BTRFS=--nodiscard"
      ];
    };
}

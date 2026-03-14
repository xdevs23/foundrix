{
  config,
  pkgs,
  lib,
  modulesPath,
  namespaced,
  namespacedCfg,
  foundrixModules,
  traitTypes,
  ...
}:
let
  partitionIds = config.foundrix.config.image.partition-ids;
  storePartitionLabel = config.image.repart.partitions.${partitionIds.store}.repartConfig.Label;
  updateMethod = config.foundrix.traits.image.updateMethod;
  hasVersionedUpdates = updateMethod == traitTypes.image.updateMethod.systemd-sysupdate;
in
{
  imports = [
    "${modulesPath}/image/repart.nix"
    foundrixModules.framework.repart-disk-image
    foundrixModules.config.filesystem.nix-store-erofs
    ../partition-ids.nix
  ];

  options = namespaced __curPos {
    compression = lib.mkOption {
      type = lib.types.str;
      default = "lz4hc";
      description = "Compression algorithm for erofs (lz4hc, lzma, etc.)";
    };

    sizeMin = lib.mkOption {
      type = lib.types.str;
      default = "4G";
      description = "Minimum size for the store partition";
    };

    labelPrefix = lib.mkOption {
      type = lib.types.str;
      default = "store";
      description = "Label for the store partition (version appended when image.updateMethod is systemd-sysupdate)";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      # Custom partition type GUID for nix store
      storeTypeGuid = "00000000-0000-4000-9000-000000000040";
      # Version suffix only for A/B update schemes
      partitionLabel =
        if hasVersionedUpdates then
          "${cfg.labelPrefix}_${config.system.image.version}"
        else
          cfg.labelPrefix;
    in
    {
      image.repart.partitions.${partitionIds.store} = {
        storePaths = [ config.system.build.toplevel ];
        # Store contents at root of partition - partition mounts to /nix/store
        nixStorePrefix = "/";

        repartConfig = {
          Type = lib.toLower storeTypeGuid;
          Label = partitionLabel;
          UUID = lib.toLower "00000000-0000-4000-9000-100000000040";
          Format = "erofs";
          Compression = cfg.compression;
          ReadOnly = "yes";
          SizeMinBytes = cfg.sizeMin;
          SplitName = "store";
        };
      };

      # Default /nix/store filesystem config pointing to store partition
      foundrix.config.filesystem.nix-store-erofs = {
        device = lib.mkDefault "/dev/disk/by-partlabel/${storePartitionLabel}";
      };

      foundrix.traits.filesystem.readOnlyStore = true;

      fileSystems."/nix/store".neededForBoot = lib.mkDefault true;

      boot.initrd.supportedFilesystems.erofs = true;
      boot.supportedFilesystems.erofs = true;

      # Configure OTA artifact for store partition when A/B updates enabled
      foundrix.framework = lib.optionalAttrs hasVersionedUpdates {
        ota-build.artifacts."store_${config.system.image.version}.img" = {
          source = "${config.system.build.image}/${config.image.baseName}.store.raw";
        };
      };
    };
}

# A/B slot partitioning for atomic updates via systemd-sysupdate.
#
# This module adds an empty store partition alongside the active store partition.
# systemd-sysupdate writes updates to the empty slot, then reboots into it.
# The previous slot becomes the new empty slot, enabling rollback.
{
  config,
  lib,
  namespaced,
  namespacedCfg,
  foundrixModules,
  ...
}:
let
  partitionIds = config.foundrix.config.image.partition-ids;
  # Custom partition type GUID for nix store
  storeTypeGuid = "00000000-0000-4000-9000-000000000040";
in
{
  imports = [
    ../partition-ids.nix
  ];

  options = namespaced __curPos {
    emptySlotSize = lib.mkOption {
      type = lib.types.str;
      default = "4G";
      description = "Size of the empty A/B slot partition";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      image.repart.partitions.${partitionIds.storeEmpty} = {
        repartConfig = {
          Type = lib.toLower storeTypeGuid;
          UUID = lib.toLower "00000000-0000-4000-9000-100000000050";
          Label = "_empty";
          Minimize = "off";
          SizeMinBytes = cfg.emptySlotSize;
          SplitName = "-"; # Don't create a split file for empty partition
        };
      };
    };
}

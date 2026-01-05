{
  lib,
  namespaced,
  ...
}:
{
  options = namespaced __curPos {
    esp = lib.mkOption {
      type = lib.types.str;
      default = "10-esp";
      readOnly = true;
      description = "Partition ID for the EFI System Partition";
    };

    main = lib.mkOption {
      type = lib.types.str;
      default = "20-main";
      readOnly = true;
      description = "Partition ID for the main system partition (btrfs-writable)";
    };

    store = lib.mkOption {
      type = lib.types.str;
      default = "30-store";
      readOnly = true;
      description = "Partition ID for the read-only store partition (erofs)";
    };

    storeEmpty = lib.mkOption {
      type = lib.types.str;
      default = "35-store-empty";
      readOnly = true;
      description = "Partition ID for the empty A/B slot store partition";
    };

    storeVerity = lib.mkOption {
      type = lib.types.str;
      default = "20-store-verity";
      readOnly = true;
      description = "Partition ID for the store verity hash partition";
    };

    storeVerityEmpty = lib.mkOption {
      type = lib.types.str;
      default = "25-store-verity-empty";
      readOnly = true;
      description = "Partition ID for the empty A/B slot verity partition";
    };
  };
}

{
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    device = lib.mkOption {
      type = lib.types.str;
      default = "PARTLABEL=nixos";
      description = "Device path for /var mount";
    };
    fsType = lib.mkOption {
      type = lib.types.str;
      default = "btrfs";
      description = "Filesystem type for /var";
    };
    fsOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        if (namespacedCfg __curPos).fsType == "btrfs" then
          [
            "subvol=@var"
            "compress=lzo"
          ]
        else
          [ ];
      description = "Mount options for /var";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      fileSystems."/var" = {
        device = cfg.device;
        fsType = cfg.fsType;
        options = cfg.fsOptions ++ [ "noatime" ];
      };
    };
}

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
      description = "Device path for /home mount";
    };
    fsType = lib.mkOption {
      type = lib.types.str;
      default = "btrfs";
      description = "Filesystem type for /home";
    };
    fsOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        if (namespacedCfg __curPos).fsType == "btrfs" then
          [
            "subvol=@home"
            "compress=lzo"
          ]
        else
          [ ];
      description = "Mount options for /home";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      fileSystems."/home" = {
        device = cfg.device;
        fsType = cfg.fsType;
        options = cfg.fsOptions ++ [ "noatime" ];
      };
    };
}

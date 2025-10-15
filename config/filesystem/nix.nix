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
      description = "Device path for /nix mount";
    };
    fsType = lib.mkOption {
      type = lib.types.str;
      default = "btrfs";
      description = "Filesystem type for /nix";
    };
    fsOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        if (namespacedCfg __curPos).fsType == "btrfs" then
          [
            "subvol=@nixos"
            "compress=lzo"
          ]
        else
          [ ];
      description = "Mount options for /nix";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      fileSystems."/nix" = {
        device = cfg.device;
        fsType = cfg.fsType;
        options = cfg.fsOptions ++ [ "noatime" ];
      };
    };
}

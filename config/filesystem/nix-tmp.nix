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
      default = "tmpfs";
      description = "Device path for /nix/tmp mount";
    };
    fsType = lib.mkOption {
      type = lib.types.str;
      default = "tmpfs";
      description = "Filesystem type for /nix/tmp";
    };
    fsOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        if (namespacedCfg __curPos).fsType == "tmpfs" then
          [
            "size=100%"
            "mode=0755"
            "uid=0"
            "gid=0"
          ]
        else
          [ ];
      description = "Mount options for /nix/tmp";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      fileSystems."/nix/tmp" = {
        device = cfg.device;
        fsType = cfg.fsType;
        options = cfg.fsOptions ++ [ "noatime" ];
      };
      nix.settings.build-dir = lib.mkForce "/nix/tmp";
    };
}

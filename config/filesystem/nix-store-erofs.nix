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
      description = "Device path for /nix/store mount (erofs partition)";
    };

    fsOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "x-systemd.after=initrd-parse-etc.service"
        "x-systemd.device-timeout=10s"
      ];
      description = "Mount options for /nix/store";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      fileSystems."/nix/store" = {
        device = cfg.device;
        fsType = "erofs";
        options = cfg.fsOptions ++ [ "noatime" ];
      };
    };
}

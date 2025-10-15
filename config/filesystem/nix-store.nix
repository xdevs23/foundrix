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
      description = "Device path for /nix/store mount";
    };
    fsType = lib.mkOption {
      type = lib.types.str;
      default = "erofs";
      description = "Filesystem type for /nix/store";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      fileSystems."/nix/store" = {
        device = cfg.device;
        fsType = cfg.fsType;
        options = [
          "noatime"
          "x-systemd.device-timeout=10s"
          "x-systemd.after=initrd-parse-etc.service"
        ];
      };
    };
}

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
      default = "PARTUUID=${lib.toLower "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"}";
      description = "Device for the ESP partition";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      fileSystems."/boot" = {
        device = cfg.device;
        fsType = "vfat";
        options = [
          "fmask=0077"
          "dmask=0077"
          "noatime"
          "x-systemd.device-timeout=30s"
        ];
      };
    };
}

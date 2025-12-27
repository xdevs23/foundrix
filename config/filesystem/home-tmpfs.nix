{
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    size = lib.mkOption {
      type = lib.types.str;
      default = "10%";
      description = "Size of the tmpfs for /home";
    };
    mode = lib.mkOption {
      type = lib.types.str;
      default = "0755";
      description = "Permissions mode for /home";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      fileSystems."/home" = {
        fsType = "tmpfs";
        options = [
          "size=${cfg.size}"
          "mode=${cfg.mode}"
          "noatime"
        ];
        neededForBoot = true;
      };
    };
}

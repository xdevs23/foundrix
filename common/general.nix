{
  lib,
  options,
  ...
}:
{
  options = {
    foundrix.general = {
      keymap = lib.mkOption {
        type = lib.types.str;
        description = "Keymap to use like us or de";
        default = options.console.keyMap.default;
      };
      qemu.portForwards = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              host = lib.mkOption { type = lib.types.port; };
              guest = lib.mkOption { type = lib.types.port; };
            };
          }
        );
        default = [ ];
      };
      qemu.dataDevice = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      qemu.disks = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption { type = lib.types.strMatching "[a-zA-Z0-9_-]+"; };
              size = lib.mkOption {
                type = lib.types.str;
                default = "40G";
              };
            };
          }
        );
        default = [ ];
      };
    };
  };
}

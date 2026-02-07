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
        type = lib.types.listOf (lib.types.submodule {
          options = {
            host = lib.mkOption { type = lib.types.port; };
            guest = lib.mkOption { type = lib.types.port; };
          };
        });
        default = [ ];
      };
    };
  };
}

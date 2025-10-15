{ lib, options, ... }:
{
  options = {
    foundrix.general = {
      keymap = lib.mkOption {
        type = lib.types.str;
        description = "Keymap to use like us or de";
        default = options.console.keyMap.default;
      };
    };
  };
}

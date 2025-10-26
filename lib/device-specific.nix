{ lib, ... }:
{
  options = {
    device = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Short, unique name of the device hardware";
      };
    };
  };
}

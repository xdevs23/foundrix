{ lib, ... }:
{
  options = {
    device = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Short, unique name of the device hardware";
      };
      cpu = {
        threads = lib.mkOption {
          type = lib.types.int;
          description = "How many logical CPU threads your machine has";
          default = 1;
        };
      };
    };
  };
}

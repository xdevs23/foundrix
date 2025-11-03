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
      platforms = lib.mkOption {
        type = with lib.types; nullOr (listOf str);
        description = "Platforms to support. If not specified, all platforms are supported";
        default = null;
      };
      crossCompile = lib.mkOption {
        type = lib.types.bool;
        description = "Whether to allow cross-compilation";
        default = true;
      };
    };
  };
}

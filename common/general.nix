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
              host = lib.mkOption {
                type = lib.types.port;
                description = "Port on the host to forward from";
              };
              guest = lib.mkOption {
                type = lib.types.port;
                description = "Port inside the guest to forward to";
              };
            };
          }
        );
        default = [ ];
        description = "Host-to-guest TCP port forwards for the QEMU user network";
      };
      qemu.dataDevice = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Disk (by name) to attach as the data device, or null for none";
      };
      qemu.disks = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.strMatching "[a-zA-Z0-9_-]+";
                description = "Identifier for the disk image";
              };
              size = lib.mkOption {
                type = lib.types.str;
                default = "40G";
                description = "Disk image size (e.g. 40G)";
              };
            };
          }
        );
        default = [ ];
        description = "Additional virtual disks to create and attach to the QEMU guest";
      };
    };
  };
}

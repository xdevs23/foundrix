{
  lib,
  config,
  ...
}:
{
  options = {
    foundrix.filesystem.nixStore = {
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
  };

  config = {
    fileSystems."/nix/store" = {
      device = config.foundrix.filesystem.nixStore.device;
      fsType = config.foundrix.filesystem.nixStore.fsType;
      options = [
        "noatime"
        "x-systemd.device-timeout=10s"
        "x-systemd.after=initrd-parse-etc.service"
      ];
    };
  };
}

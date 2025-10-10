{
  lib,
  config,
  ...
}:
{
  options = {
    foundrix.filesystem.home = {
      device = lib.mkOption {
        type = lib.types.str;
        default = "PARTLABEL=nixos";
        description = "Device path for /home mount";
      };
      fsType = lib.mkOption {
        type = lib.types.str;
        default = "btrfs";
        description = "Filesystem type for /home";
      };
      fsOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default =
          if config.foundrix.filesystem.home.fsType == "btrfs" then
            ["subvol=@home" "compress=lzo"]
          else
            [];
        description = "Mount options for /home";
      };
    };
  };

  config = {
    fileSystems."/home" = {
      device = config.foundrix.filesystem.home.device;
      fsType = config.foundrix.filesystem.home.fsType;
      options = config.foundrix.filesystem.home.fsOptions ++ ["noatime"];
    };
  };
}
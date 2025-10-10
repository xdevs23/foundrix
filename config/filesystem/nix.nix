{
  lib,
  config,
  ...
}:

{
  options = {
    foundrix.filesystem.nix = {
      device = lib.mkOption {
        type = lib.types.str;
        default = "PARTLABEL=nixos";
        description = "Device path for /nix mount";
      };
      fsType = lib.mkOption {
        type = lib.types.str;
        default = "btrfs";
        description = "Filesystem type for /nix";
      };
      fsOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default =
          if config.foundrix.filesystem.nix.fsType == "btrfs" then
            ["subvol=@nixos" "compress=lzo"]
          else
            [];
        description = "Mount options for /nix";
      };
    };
  };

  config = {
    fileSystems."/nix" = {
      device = config.foundrix.filesystem.nix.device;
      fsType = config.foundrix.filesystem.nix.fsType;
      options = config.foundrix.filesystem.nix.fsOptions ++ ["noatime"];
    };
  };
}
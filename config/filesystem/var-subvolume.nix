{
  config,
  lib,
  foundrixModules,
  traitTypes,
  ...
}:
let
  subvolume = "var";
  nixFilesystem = config.foundrix.config.filesystem.nix;
in
{
  imports = [
    foundrixModules.config.image.store.btrfs-writable
    foundrixModules.config.filesystem.var
  ];

  foundrix.traits.filesystem.varProvisioner = traitTypes.filesystem.varProvisioner.main-subvolume;

  foundrix.config.image.store.btrfs-writable.extraSubvolumes = [ subvolume ];

  foundrix.config.filesystem.var = {
    inherit (nixFilesystem) device fsType;
    fsOptions = [
      "subvol=${subvolume}"
    ]
    ++ lib.filter (option: !lib.hasPrefix "subvol=" option) nixFilesystem.fsOptions;
  };
}

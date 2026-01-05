{
  foundrixModules,
  lib,
  ...
}:
{
  imports = [
    foundrixModules.config.image.store.btrfs-writable
    foundrixModules.config.image.boot.systemd-boot-bios
  ];

  system.stateVersion = lib.mkDefault (builtins.substring 0 5 lib.version);
}

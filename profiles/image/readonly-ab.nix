# Read-only store with A/B slot layout.
#
# Technical characteristics:
# - erofs read-only nix store (compressed, fast reads)
# - A/B slot partitions for atomic updates via systemd-sysupdate
# - UEFI boot with systemd-boot
#
# Usage:
#   imports = [
#     foundrixModules.profiles.image.readonly-ab
#     foundrixModules.config.runtime.repart.data  # for /var partition
#   ];
#
#   foundrix.config.image.device.dataDevice = "/dev/nvme0n1";
{
  foundrixModules,
  lib,
  ...
}:
{
  imports = [
    foundrixModules.config.image.store.erofs-readonly
    foundrixModules.config.image.boot.systemd-boot
    foundrixModules.config.image.slots.ab
  ];

  system.stateVersion = lib.mkDefault (builtins.substring 0 5 lib.version);
}

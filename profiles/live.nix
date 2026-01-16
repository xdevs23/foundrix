# Live bootable image profile.
#
# Technical characteristics:
# - erofs read-only nix store (compressed, fast reads)
# - tmpfs volatile root (no persistent state)
# - UEFI boot with systemd-boot
# - No system updates (static partition labels)
#
# Usage:
#   imports = [
#     foundrixModules.profiles.live
#   ];
#
#   # Optionally configure greetd autostart:
#   foundrix.config.greetd-autostart = {
#     package = pkgs.writeShellScriptBin "installer" ''...'';
#     user = "nixos";
#   };
{
  foundrixModules,
  lib,
  ...
}:
{
  imports = [
    foundrixModules.profiles.minimal-image
    foundrixModules.config.image.store.erofs-readonly
    foundrixModules.config.image.boot.systemd-boot
  ];

  system.stateVersion = lib.mkDefault (builtins.substring 0 5 lib.version);
}

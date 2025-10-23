{
  pkgs,
  lib,
  foundrixModules,
  ...
}:
{
  imports = [
    foundrixModules.profiles.desktop-base
    foundrixModules.config.appimage
    foundrixModules.config.media.pipewire
  ];

  programs.gnupg.agent.enable = lib.mkDefault true;

  # Graphical environment basics
  fonts.fontDir.enable = lib.mkDefault true;
  gtk.iconCache.enable = lib.mkDefault true;
  services.libinput.enable = lib.mkDefault true;
  xdg.icons.enable = lib.mkDefault true;

  system.stateVersion = lib.mkDefault (builtins.substring 0 5 pkgs.lib.version);
}

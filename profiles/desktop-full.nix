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
    foundrixModules.config.compat
    foundrixModules.config.gstreamer
  ];

  programs.gnupg.agent.enable = lib.mkDefault true;

  # Graphical environment basics
  fonts.fontDir.enable = lib.mkDefault true;
  gtk.iconCache.enable = lib.mkDefault true;
  services.libinput.enable = lib.mkDefault true;
  xdg.icons.enable = lib.mkDefault true;

  services.gvfs.enable = true;
  programs.dconf.enable = true;

  services.printing.enable = lib.mkDefault true;
  hardware.sane.enable = lib.mkDefault true;

  system.stateVersion = lib.mkDefault (builtins.substring 0 5 pkgs.lib.version);
}

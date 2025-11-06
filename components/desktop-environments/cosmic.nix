{ lib, foundrixModules, ... }:
{
  imports = [
    foundrixModules.config.graphics.gtk
    foundrixModules.config.graphics.qt
  ];

  services.displayManager.cosmic-greeter.enable = lib.mkDefault true;
  services.desktopManager.cosmic.enable = lib.mkDefault true;
}

{ lib, ... }:
{
  services.displayManager.cosmic-greeter.enable = lib.mkDefault true;
  services.desktopManager.cosmic.enable = lib.mkDefault true;
}

{ pkgs, ... }:
{
  hardware.keyboard.qmk.enable = true;
  services.udev.packages = [ pkgs.vial ];
  environment.systemPackages = [ pkgs.vial ];
}

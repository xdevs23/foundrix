# Support for connected Apple devices
{ pkgs, ... }:
{
  services.usbmuxd = {
    enable = true;
    package = pkgs.usbmuxd2;
  };
  environment.systemPackages = with pkgs; [
    ifuse
    libimobiledevice
    idevicerestore
  ];
}

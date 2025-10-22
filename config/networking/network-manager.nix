{ lib, ... }:
{
  options = { };

  config = {
    networking.networkmanager.enable = true;
    networking.useDHCP = lib.mkDefault true;
    systemd.services.NetworkManager-wait-online.enable = lib.mkDefault false;
  };
}

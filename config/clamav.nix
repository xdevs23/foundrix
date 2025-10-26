{ lib, ... }:
{
  services.clamav = {
    updater.enable = true;
    fangfrisch.enable = true;
    daemon.enable = true;
    updater.interval = lib.mkDefault "*-*-* 00/4:00:00";
    fangfrisch.interval = lib.mkDefault "*-*-* 00/4:00:00";
  };
}

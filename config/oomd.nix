{ lib, ... }:
{
  systemd.oomd = {
    enable = lib.mkDefault true;
    enableRootSlice = lib.mkDefault true;
    enableUserSlices = lib.mkDefault true;
    enableSystemSlice = lib.mkDefault true;
    extraConfig = {
      "DefaultMemoryPressureDurationSec" = "20s";
    };
  };
}

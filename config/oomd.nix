{ lib, ... }:
{
  systemd.oomd = {
    enable = lib.mkDefault true;
    enableRootSlice = lib.mkDefault true;
    enableUserSlices = lib.mkDefault true;
    enableSystemSlice = lib.mkDefault true;
  }
  // (
    let
      settings = {
        DefaultMemoryPressureDurationSec = "20s";
      };
    in
    if lib.versionAtLeast lib.version "25.10" then
      {
        settings.OOM = settings;
      }
    else
      {
        extraConfig = settings;
      }
  );
}

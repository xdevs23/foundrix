{ pkgs, lib, ... }:
{
  programs.adb.enable = true;
  services.udev.packages = lib.mkIf (lib.versionOlder lib.version "25.10") pkgs.android-udev-rules;
}

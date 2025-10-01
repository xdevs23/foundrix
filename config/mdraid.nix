# This module provides a simpler version of what
# boot.swraid.enable does
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.mdadm ];
  services.udev.packages = [ pkgs.mdadm ];
  systemd.packages = [ pkgs.mdadm ];
}
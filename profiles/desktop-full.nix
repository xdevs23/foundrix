{
  pkgs,
  lib,
  foundrixModules,
  ...
}:
{
  imports = with foundrixModules; [
    config.security.pam-login-limits
    config.appimage
  ];

  services.dbus.enable = lib.mkDefault true;
  environment.systemPackages = with pkgs; [
    lsof
    file
  ];
  boot = {
    kernelPackages = lib.mkOverride 101 pkgs.linuxPackages_latest;
    tmp.useTmpfs = lib.mkDefault true;
    kernelParams = [ "boot.shell_on_fail" ];
  };

}

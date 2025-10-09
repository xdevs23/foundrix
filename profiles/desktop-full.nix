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
    config.oomd
  ];

  services.dbus.enable = lib.mkDefault true;
  programs.gnupg.agent.enable = lib.mkDefault true;
  services.bpftune.enable = lib.mkDefault true;

  boot.loader.systemd-boot = {
    enable = lib.mkDefault true;
    configurationLimit = lib.mkDefault 5;
    consoleMode = lib.mkDefault "max";
  };

  # Graphical environment basics
  fonts.fontDir.enable = lib.mkDefault true;
  gtk.iconCache.enable = lib.mkDefault true;
  services.libinput.enable = lib.mkDefault true;
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

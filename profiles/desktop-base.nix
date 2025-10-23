{
  pkgs,
  lib,
  foundrixModules,
  mkMaybeDefault,
  config,
  ...
}:
{
  imports = [
    foundrixModules.config.security.pam-login-limits
    foundrixModules.config.oomd
  ];

  services.dbus.enable = lib.mkDefault true;
  services.bpftune.enable = lib.mkDefault true;

  boot.loader.systemd-boot = {
    enable = lib.mkDefault true;
    configurationLimit = lib.mkDefault 5;
    consoleMode = lib.mkDefault "max";
  };

  console = {
    font = lib.mkDefault "Lat2-Terminus16";
    keyMap = mkMaybeDefault config.foundrix.general.keymap;
    earlySetup = true;
  };

  users.mutableUsers = false;

  environment.systemPackages = with pkgs; [
    lsof
    file
  ];
  boot = {
    kernelPackages = lib.mkOverride 101 pkgs.linuxPackages_latest;
    tmp.useTmpfs = lib.mkDefault true;
    kernelParams = [ "boot.shell_on_fail" ];
    initrd = {
      systemd.enable = true;
    };
  };

  system.stateVersion = lib.mkDefault (builtins.substring 0 5 pkgs.lib.version);
}

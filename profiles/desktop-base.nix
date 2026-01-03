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
    foundrixModules.config.networking.network-manager
    foundrixModules.config.networking.network-discovery
    foundrixModules.config.basic-baremetal
    foundrixModules.config.basic-fonts
    foundrixModules.config.basic-user-system
    foundrixModules.config.nix
  ];

  services.dbus.enable = lib.mkDefault true;
  services.bpftune.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isx86_64;

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

  services.timesyncd.enable = lib.mkDefault true;
  users.mutableUsers = false;

  environment.systemPackages = with pkgs; [
    lsof
    file
  ];
  boot = {
    kernelPackages = lib.mkOverride 101 pkgs.linuxPackages_latest;
    tmp = {
      useTmpfs = lib.mkDefault true;
      tmpfsSize = "100%";
    };
    kernelParams = [
      "boot.shell_on_fail"
      "quiet"
      "loglevel=2"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
    initrd = {
      systemd.enable = true;
    };
  };

  system.stateVersion = lib.mkDefault (builtins.substring 0 5 pkgs.lib.version);
}

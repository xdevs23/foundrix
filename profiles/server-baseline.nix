{
  pkgs,
  lib,
  mkMaybeDefault,
  config,
  foundrixModules,
  ...
}:
{
  imports = [
    foundrixModules.config.oomd
    foundrixModules.config.networking.network-discovery
  ];

  services.dbus.enable = lib.mkDefault true;

  users.mutableUsers = false;

  environment.systemPackages = with pkgs; [
    lsof
    file
  ];
  boot = {
    kernelPackages = lib.mkOverride 101 pkgs.linuxPackages_latest;
    tmp.useTmpfs = lib.mkDefault true;
    loader.systemd-boot = {
      enable = lib.mkDefault true;
      configurationLimit = lib.mkDefault 5;
      consoleMode = lib.mkDefault "max";
    };
  };

  console = {
    keyMap = mkMaybeDefault config.foundrix.general.keymap;
    earlySetup = true;
  };

  system.stateVersion = lib.mkDefault (builtins.substring 0 5 lib.version);
}

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
    foundrixModules.config.basic-baremetal
    foundrixModules.config.oomd
    foundrixModules.config.networking.network-discovery
    foundrixModules.config.security.all
    foundrixModules.config.nix
  ];

  services.dbus.enable = lib.mkDefault true;
  services.bpftune.enable = lib.mkDefault pkgs.stdenv.hostPlatform.isx86_64;
  services.timesyncd.enable = lib.mkDefault true;

  nix.settings.trusted-users = [
    "root"
    "@wheel"
  ];

  users.mutableUsers = false;

  system.nixos-init.enable = lib.mkDefault true;
  boot.initrd.systemd.enable = lib.mkDefault true;
  system.etc.overlay.enable = lib.mkDefault true;
  services.userborn.enable = lib.mkDefault true;

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

{
  foundrixModules,
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    foundrixModules.profiles.desktop-base
    foundrixModules.config.kodi-gbm
    foundrixModules.config.oomd
    foundrixModules.config.networking.network-discovery
  ];

  foundrix.config.kodi-gbm = {
    user = "kodi";
  };

  users.users.${config.foundrix.config.kodi-gbm.user} = {
    isNormalUser = true;
    extraGroups = [ ];
    password = lib.mkDefault config.foundrix.config.kodi-gbm.user;
    uid = lib.mkDefault 1100;
    shell = pkgs.bash;
  };

  users.groups.${config.foundrix.config.kodi-gbm.user}.gid =
    config.users.users.${config.foundrix.config.kodi-gbm.user}.uid;

  users.mutableUsers = lib.mkDefault false;
  services.displayManager.autoLogin.user = config.foundrix.config.kodi-gbm.user;

  boot.initrd.systemd.enable = true;
  boot.tmp.cleanOnBoot = true;

  networking.hostName = lib.mkOverride 1100 "htpc";

  services.timesyncd.enable = lib.mkDefault true;
  services.bpftune.enable = true;
  services.gvfs.enable = true;
  programs.dconf.enable = true;

  networking.firewall.allowedTCPPorts = [
    8081
    9090
  ];

  boot.uki.name = lib.mkDefault "htos";
  system.nixos.distroId = lib.mkDefault "htos";
  system.nixos.distroName = lib.mkDefault "Home Theater OS";
  system.image.id = lib.mkDefault "htpc-htos";

  system.stateVersion = lib.mkDefault (builtins.substring 0 5 pkgs.lib.version);
}

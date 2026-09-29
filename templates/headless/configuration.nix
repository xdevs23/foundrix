{
  foundrixModules,
  lib,
  pkgs,
  config,
  ...
}:
# To save you a few keystores, assuming you only need one user, here's where you can set the username.
let
  userName = "user";
in
{
  imports = [
    foundrixModules.profiles.server-baseline
    foundrixModules.config.home-manager
    foundrixModules.config.shell.zsh.lite
    ./home.nix
  ];

  # Configure your users here
  users.users.${userName} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    uid = 1000;
    initialPassword = lib.warn "You have to set your own hashed password and remove the initial password." "Hash your password using mkpasswd and set it below. Remove the initialPassword lines afterwards.";
    #hashedPassword = "$y$...";
    shell = pkgs.zsh;
  };
  users.groups.${userName}.gid = config.users.users.${userName}.uid;
  # You can also set a root password here
  #users.users.root.hashedPassword = config.users.users.${userName}.hashedPassword;

  # Usually the state version is all you need. There is a separate file for home configuration.
  home-manager.users.${userName}.home.stateVersion = "26.05";

  security.sudo = {
    enable = true;
  };

  system.stateVersion = "26.05";
}

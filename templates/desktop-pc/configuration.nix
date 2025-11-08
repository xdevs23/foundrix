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
    foundrixModules.profiles.desktop-full
    foundrixModules.config.graphics.cursors.breezex-rosepine
    foundrixModules.config.graphics.fonts.adwaita-sans
    foundrixModules.config.shell.zsh.lite
    ./home.nix
    ./dconf.nix
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
  home-manager.users.${userName}.home.stateVersion = "25.05";

  security.sudo = {
    enable = true;
  };

  # Here's a selection of fonts.
  # Liberation Sans is provided by default as part of the desktop-base profile and
  # Adwaita Sans is imported at the top.
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.hasklug
    dejavu_fonts
    material-icons
    material-symbols
    roboto
    hasklig
    iosevka
    iosevka-comfy.comfy
  ];

  system.stateVersion = "25.05";
}

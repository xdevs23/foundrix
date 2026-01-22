{
  foundrixModules,
  lib,
  pkgs,
  config,
  ...
}:
let
  userName = "admin";
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
    shell = pkgs.zsh;
    # Generate with: nix run nixpkgs#mkpasswd
    initialPassword = lib.warn "Set hashedPassword and remove initialPassword" "changeme";
    #hashedPassword = "$y$...";
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here
      #"ssh-ed25519 AAAA..."
    ];
  };
  users.groups.${userName}.gid = config.users.users.${userName}.uid;

  home-manager.users.${userName}.home.stateVersion = "25.11";

  security.sudo.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Allow root SSH access with user's keys
  users.users.root.openssh.authorizedKeys.keys =
    config.users.users.${userName}.openssh.authorizedKeys.keys;

  nix.settings.trusted-users = [
    "root"
    "@wheel"
  ];

  # Image identification
  boot.uki.name = "my-server";

  system.stateVersion = "25.11";
}

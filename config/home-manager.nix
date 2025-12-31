{
  inputs,
  lib,
  config,
  foundrixModules,
  foundrixPackages,
  foundrixInputs,
  ...
}:
{
  imports = [
    foundrixInputs.home-manager.nixosModules.home-manager
  ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs foundrixModules foundrixPackages; };
  };
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];
  _module.args.libHm = foundrixInputs.home-manager.lib;

  # Setup directories for home-manager users
  systemd.services = lib.mapAttrs' (userName: userCfg: {
    name = "home-manager-${userName}-setup";
    value = rec {
      description = "Setup directories for Home Manager (${userName})";
      wantedBy = [ "home-manager-${userName}.service" ];
      before = wantedBy;
      requires = [ "nix-store-registration.service" ];
      after = requires;

      serviceConfig = {
        Type = "oneshot";
        User = userName;
      };

      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "/nix/var/nix/db/.registered";
        OnFailure = "emergency.target";
      };

      script = ''
        [ -d "$HOME/.local/state/nix/profiles" ] && [ -L "$HOME/.local/state/nix/profiles/profile" ] && exit 0
        echo "Setting up directories for $HOME"
        mkdir -p $HOME/.local/state/nix/profiles
        mkdir -p $HOME/.local/state/home-manager/gcroots
        ln -sf \
          /etc/profiles/per-user/${userName} \
          $HOME/.local/state/nix/profiles/profile-1-link
        ln -sf \
          profile-1-link \
          $HOME/.local/state/nix/profiles/profile
      '';
    };
  }) (lib.filterAttrs (_: user: user.isNormalUser) (config.users.users));
}

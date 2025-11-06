{
  pkgs,
  config,
  lib,
  namespaced,
  ...
}:
{
  options = namespaced __curPos {
    build.prebuiltHomes = lib.mkOption {
      type = with lib.types; attrsOf package;
      description = "Packages of prebuilt homes";
    };
  };
  config =
    let
      hmUsers = config.home-manager.users;
      userConfigs = lib.mapAttrs' (
        userName: userCfg:
        lib.nameValuePair userName rec {
          userId = config.users.users.${userName}.uid;
          groupId = config.users.groups.${userName}.gid or userId;
          homeFiles = userCfg.home-files;
          homePath = userCfg.home.path;
        }
      ) hmUsers;
      prebuiltHomes = lib.mapAttrs (
        userName: cfg:
        pkgs.runCommand "${userName}-home"
          {
            dontFixup = true;
            allowSubstitutes = false;
          }
          ''
            mkdir -p $out
            cp -R --reflink=auto --preserve=timestamps,links ${cfg.homeFiles}/. $out/
            ln -s ${cfg.homePath} $out/.nix-profile
          ''
      ) userConfigs;
    in
    lib.mkMerge [
      (namespaced __curPos {
        build.prebuiltHomes = prebuiltHomes;
      })
      {
        home-manager.useUserPackages = lib.mkForce false;
        home-manager.sharedModules = [
          {
            programs.home-manager.enable = lib.mkForce false;
          }
        ];
        fileSystems = lib.mkMerge (
          lib.mapAttrsToList (userName: cfg: {
            "/home/${userName}" = {
              device = "overlay";
              fsType = "overlay";
              options = [
                "lowerdir=${prebuiltHomes.${userName}}"
                "upperdir=/var/home/${userName}/upper"
                "workdir=/var/home/${userName}/work"
                "x-systemd.requires=systemd-tmpfiles-setup.service"
              ];
            };
          }) userConfigs
        );
        systemd.tmpfiles.settings = lib.mkMerge (
          lib.mapAttrsToList (userName: cfg: {
            "home-${userName}" = {
              "/var/home/${userName}" = {
                d = {
                  mode = "0750";
                  user = toString cfg.userId;
                  group = toString cfg.groupId;
                };
              };
              "/var/home/${userName}/upper" = {
                d = {
                  mode = "0750";
                  user = toString cfg.userId;
                  group = toString cfg.groupId;
                };
              };
              "/var/home/${userName}/work" = {
                d = {
                  mode = "0750";
                  user = toString cfg.userId;
                  group = toString cfg.groupId;
                };
              };
            };
          }) userConfigs
        );
        systemd.services = lib.mkMerge (
          lib.mapAttrsToList (userName: cfg: {
            "home-manager-${userName}".enable = false;
          }) userConfigs
        );
      }
    ];
}

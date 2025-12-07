{
  pkgs,
  config,
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    build.prebuiltHomes = lib.mkOption {
      type = with lib.types; attrsOf package;
      description = "Packages of prebuilt homes";
    };
    prepareOnEveryBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to prepare home directories on every boot. When enabled, the base layer is refreshed each boot to pick up changes. When disabled, the base is only prepared once.";
    };
  };
  config =
    let
      cfg = namespacedCfg __curPos;
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
        systemd.services = lib.mkMerge (
          lib.mapAttrsToList (
            userName: userCfg:
            let
              prebuiltHome = prebuiltHomes.${userName};
              copiedHome = "/var/home/${userName}/base";
            in
            {
              "prepare-home-${userName}" = rec {
                description = "Prepare home directory base for ${userName}";
                requiredBy = [ "home-${userName}.mount" ];
                before = requiredBy;
                requires = [ "systemd-tmpfiles-setup.service" ];
                after = requires;
                unitConfig = {
                  DefaultDependencies = false;
                }
                // lib.optionalAttrs (!cfg.prepareOnEveryBoot) {
                  ConditionPathExists = "!${copiedHome}/.nix-profile";
                };
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  ExecStart = pkgs.writeShellScript "prepare-home-${userName}" ''
                    mkdir -p ${copiedHome}
                    ${lib.getExe pkgs.rsync} -rlc --delete ${prebuiltHome}/. ${copiedHome}/
                    chown -R ${toString userCfg.userId}:100 ${copiedHome}
                    chmod -R u+w ${copiedHome}
                  '';
                };
              };
              "home-manager-${userName}".enable = false;
            }
          ) userConfigs
        );
        systemd.mounts = lib.flatten (
          lib.mapAttrsToList (
            userName: cfg:
            let
              copiedHome = "/var/home/${userName}/base";
            in
            rec {
              where = "/home/${userName}";
              what = "overlay";
              type = "overlay";
              options = "lowerdir=${copiedHome},upperdir=/var/home/${userName}/upper,workdir=/var/home/${userName}/work,userxattr";
              unitConfig.DefaultDependencies = false;
              before = [ "multi-user.target" ];
              wantedBy = [ "multi-user.target" ];
              requires = [
                "prepare-home-${userName}.service"
                "systemd-tmpfiles-setup.service"
              ];
              after = requires;
              description = "Overlay home directory for ${userName}";
            }
          ) userConfigs
        );

        systemd.tmpfiles.settings = lib.mkMerge (
          lib.mapAttrsToList (userName: cfg: {
            "home-${userName}" = {
              "/var/home/${userName}" = {
                d = {
                  mode = "0750";
                  user = toString cfg.userId;
                  group = "100";
                };
              };
              "/var/home/${userName}/base" = {
                d = {
                  mode = "0750";
                  user = toString cfg.userId;
                  group = "100";
                };
              };
              "/var/home/${userName}/upper" = {
                d = {
                  mode = "0750";
                  user = toString cfg.userId;
                  group = "100";
                };
              };
              "/var/home/${userName}/work" = {
                d = {
                  mode = "0750";
                  user = toString cfg.userId;
                  group = "100";
                };
              };
            };
          }) userConfigs
        );
      }
    ];
}

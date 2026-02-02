{
  inputs,
  pkgs,
  lib,
  config,
  namespaced,
  namespacedCfg,
  mkConfigurableUsersOption,
  applyHomeManagerUsers,
  ...
}:
let
  cfg = namespacedCfg __curPos;
in
{
  options = namespaced __curPos {
    users = mkConfigurableUsersOption {
      description = "Which users to apply quickshell services to. Defaults to all users.";
    };
    instances = lib.mkOption {
      description = "Instances of quickshell to build";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            package = lib.mkOption {
              type = lib.types.package;
              default = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
              description = "The quickshell package to use for this instance";
            };
            configPath = lib.mkOption {
              type = with lib.types; either str path;
              description = "Path to where the quickshell files are contained within";
            };
            additionalArgs = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Additional arguments to pass to quickshell";
            };
            modules = lib.mkOption {
              type = with lib.types; attrsOf (either str path);
              default = { };
              description = "Additional QML modules to symlink into the config directory (name → path)";
            };
            lockscreen = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether this instance is a session lockscreen (sets up PAM)";
            };
            pamConfig = lib.mkOption {
              type = lib.types.lines;
              default = ''
                ${lib.optionalString config.services.fprintd.enable "auth sufficient pam_fprintd.so"}
                auth required pam_unix.so
              '';
              description = "PAM configuration (only used when lockscreen = true)";
            };
            service.enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to create a systemd user service for this instance";
            };
            environment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Environment variables to set when running quickshell";
            };
          };
        }
      );
      default = { };
    };
    build.instances = lib.mkOption {
      description = "Instances of quickshell build outputs, matches provided instances";
      type =
        with lib.types;
        attrsOf (submodule {
          options.package = lib.mkOption {
            type = lib.types.package;
            description = "Built package that starts quickshell with the provided configuration";
          };
        });
    };
  };
  config = lib.mkMerge [
    (namespaced __curPos {
      build.instances = lib.mapAttrs (name: instanceCfg:
        let
          configDir =
            if instanceCfg.modules == { } then instanceCfg.configPath
            else pkgs.runCommand "quickshell-${name}-config" { } ''
              mkdir -p $out
              cp -r ${instanceCfg.configPath}/* $out/
              ${lib.concatStringsSep "\n" (lib.mapAttrsToList (modName: modPath: ''
                rm -rf $out/${modName}
                ln -s ${modPath} $out/${modName}
              '') instanceCfg.modules)}
            '';
        in {
          package = pkgs.writeShellScriptBin "quickshell-${name}" ''
            export QS_NO_RELOAD_POPUP=1
            export QS_NO_WATCH=1
            ${lib.optionalString (instanceCfg.lockscreen && config.services.fprintd.enable) ''
              export LOCKSCREEN_FINGERPRINT_ENABLED=1
            ''}
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") instanceCfg.environment)}
            ${lib.getExe instanceCfg.package} \
              -c "${configDir}" ${instanceCfg.additionalArgs}
          '';
        }
      ) cfg.instances;
    })
    {
      security.pam.services = lib.mkMerge (
        lib.mapAttrsToList (name: instanceCfg:
          lib.mkIf instanceCfg.lockscreen { "quickshell-${name}".text = instanceCfg.pamConfig; }
        ) cfg.instances
      );
    }
    {
      home-manager = applyHomeManagerUsers cfg.users {
        systemd.user.services = lib.mkMerge (
          lib.mapAttrsToList (name: instanceCfg:
            lib.mkIf instanceCfg.service.enable {
              "quickshell-${name}" = {
                Unit = rec {
                  Description = "Quickshell ${name}";
                  PartOf = [ "graphical-session.target" ];
                  After = PartOf;
                };
                Service = {
                  Type = "simple";
                  ExecStart = lib.getExe cfg.build.instances.${name}.package;
                  Restart = "on-failure";
                  RestartSec = 1;
                };
                Install.WantedBy = lib.mkIf (!instanceCfg.lockscreen) [ "graphical-session.target" ];
              };
            }
          ) cfg.instances
        );
      };
    }
  ];
}

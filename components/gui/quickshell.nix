{
  inputs,
  pkgs,
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    instances = lib.mkOption {
      description = "Instances of quickshell to build";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            configPath = lib.mkOption {
              type = with lib.types; either str path;
              description = "Path to where the quickshell files are contained within";
            };
            additionalArgs = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Additional arguments to pass to quickshell";
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
  config = namespaced __curPos {
    build.instances = lib.mapAttrs (name: cfg: {
      package = pkgs.writeShellScriptBin "quickshell-wrapped" ''
        export QS_NO_RELOAD_POPUP=1
        ${lib.getExe inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default} \
          -c "${cfg.configPath}" ${cfg.additionalArgs}
      '';
    }) (namespacedCfg __curPos).instances;
  };
}

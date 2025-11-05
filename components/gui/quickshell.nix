{
  inputs,
  system,
  pkgs,
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    instances = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            configPath = lib.mkOption {
              type = with lib.types; either str path;
            };
            additionalArgs = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
          };
        }
      );
      default = { };
    };
    build.instances = lib.mkOption {
      type =
        with lib.types;
        attrsOf (submodule {
          options.package = lib.mkOption {
            type = lib.types.package;
          };
        });
    };
  };
  config = namespaced __curPos {
    build.instances = lib.mapAttrs (name: cfg: {
      package = pkgs.writeShellScriptBin "quickshell-wrapped" ''
        export QS_NO_RELOAD_POPUP=1
        ${lib.getExe inputs.quickshell.packages.${system}.default} \
          -c "${cfg.configPath}" ${cfg.additionalArgs}
      '';
    }) (namespacedCfg __curPos).instances;
  };
}

{
  lib,
  pkgs,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.writeShellScriptBin "interactive-shell" ''
        exec ${pkgs.runtimeShell} -i
      '';
      description = "Package providing the auto-start executable";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "User to run the auto-start command as";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = lib.getExe cfg.package;
            user = cfg.user;
          };
          default_session = {
            command = lib.getExe cfg.package;
            user = cfg.user;
          };
        };
      };

      systemd.services.greetd.serviceConfig = {
        Type = "idle";
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "journal";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
      };
    };
}

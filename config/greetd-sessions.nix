{
  lib,
  pkgs,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;

  sessionModule = lib.types.submodule (
    { ... }:
    {
      options = {
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.writeShellScriptBin "interactive-shell" ''
            exec ${pkgs.runtimeShell} -i
          '';
          description = "Package providing the session executable";
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = "User to run the session as";
        };

        vt = lib.mkOption {
          type = lib.types.int;
          description = "Virtual terminal to use for this session";
        };

        conflicts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Systemd units this session conflicts with";
        };

        onFailure = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Systemd units to start if this session fails";
        };
      };
    }
  );

  greetdFormat = pkgs.formats.toml { };

  mkSessionService = name: sessionCfg: {
    description = "Greetd session: ${name}";
    conflicts = sessionCfg.conflicts;
    after = [
      "systemd-user-sessions.service"
      "getty@tty${toString sessionCfg.vt}.service"
    ];
    inherit (sessionCfg) onFailure;

    serviceConfig = {
      Type = "idle";
      ExecStart = "${lib.getExe pkgs.greetd} --config ${
        greetdFormat.generate "greetd-${name}.toml" {
          terminal.vt = sessionCfg.vt;
          initial_session = {
            command = lib.getExe sessionCfg.package;
            user = sessionCfg.user;
          };
          default_session = {
            command = lib.getExe sessionCfg.package;
            user = sessionCfg.user;
          };
        }
      }";
      TTYPath = "/dev/tty${toString sessionCfg.vt}";
      TTYReset = true;
      TTYVHangup = true;
      TTYVTDisallocate = true;
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "journal";
    };
  };
in
{
  options = namespaced __curPos {
    sessions = lib.mkOption {
      type = lib.types.attrsOf sessionModule;
      default = { };
      description = ''
        Named greetd sessions that can be started on demand.
        Each session creates a systemd service named greetd-<name>.service
        that does not start automatically.
      '';
      example = lib.literalExpression ''
        {
          flasher = {
            package = myFlasherPackage;
            user = "root";
            vt = 7;
          };
          recovery = {
            package = pkgs.writeShellScriptBin "recovery" "exec bash -i";
            user = "root";
            vt = 8;
            onFailure = [ "reboot.target" ];
          };
        }
      '';
    };
  };

  config = lib.mkIf (cfg.sessions != { }) {
    systemd.services = lib.mapAttrs' (
      name: sessionCfg: lib.nameValuePair "greetd-${name}" (mkSessionService name sessionCfg)
    ) cfg.sessions;

    security.pam.services.greetd = {
      allowNullPassword = true;
      startSession = true;
    };
  };
}

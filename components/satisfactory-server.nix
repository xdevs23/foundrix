{
  pkgs,
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    port = lib.mkOption {
      type = lib.types.port;
      default = 7777;
      description = "Game and API port (UDP + TCP)";
    };
    reliablePort = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Reliable messaging port (TCP)";
    };
    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra command-line arguments passed to the server";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for the Satisfactory server";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      steamAppId = "1690800";
      stateDir = "satisfactory";
      serverArgs = [
        "-Port=${toString cfg.port}"
        "-ReliablePort=${toString cfg.reliablePort}"
      ]
      ++ cfg.extraArgs;
    in
    {
      users.users.satisfactory = {
        isSystemUser = true;
        group = "satisfactory";
      };
      users.groups.satisfactory = { };

      systemd.services.satisfactory = {
        description = "Satisfactory Dedicated Server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        preStart = ''
          ${pkgs.steamcmd}/bin/steamcmd \
            +force_install_dir /var/lib/${stateDir}/server \
            +login anonymous \
            +app_update ${steamAppId} validate \
            +quit
        '';

        script = ''
          cd /var/lib/${stateDir}/server
          exec ${pkgs.steam-run}/bin/steam-run \
            ./FactoryServer.sh ${lib.concatStringsSep " " serverArgs}
        '';

        serviceConfig = {
          Type = "simple";
          User = "satisfactory";
          Group = "satisfactory";
          Nice = -5;
          Restart = "on-failure";
          RestartSec = 30;
          WorkingDirectory = "/var/lib/${stateDir}";

          StateDirectory = stateDir;
          StateDirectoryMode = "0750";

          # Sandboxing
          ProtectHome = true;
          ProtectSystem = "strict";
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RestrictNamespaces = true;
          LockPersonality = true;
          NoNewPrivileges = true;
          MemoryDenyWriteExecute = false; # UE needs JIT
          SystemCallArchitectures = "native";
        };
      };

      networking.firewall = lib.mkIf cfg.openFirewall {
        allowedUDPPorts = [ cfg.port ];
        allowedTCPPorts = [
          cfg.port
          cfg.reliablePort
        ];
      };
    };
}

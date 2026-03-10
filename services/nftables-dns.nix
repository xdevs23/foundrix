{
  lib,
  pkgs,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;

  connectionType = lib.types.submodule {
    options = {
      host = lib.mkOption {
        type = lib.types.str;
        description = ''
          Hostname to resolve. Use "*" for static port-based rules
          that don't require DNS resolution.
        '';
        example = "acme.zerossl.com";
      };
      ports = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        description = "Destination ports to allow";
        example = [ 443 ];
      };
      protocol = lib.mkOption {
        type = lib.types.enum [ "tcp" "udp" ];
        default = "tcp";
        description = "Transport protocol";
      };
    };
  };

  dynamicConnections = builtins.filter (c: c.host != "*") cfg.allowedConnections;

  configJson = pkgs.writeText "nftables-dns-config.json" (builtins.toJSON {
    connections = map (c: {
      inherit (c) host ports protocol;
    }) dynamicConnections;
    inherit (cfg) table chain interfaceMatch;
  });

in
{
  options = namespaced __curPos {
    enable = lib.mkEnableOption "dynamic DNS resolution for nftables outbound rules";

    dnsServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "2606:4700:4700::1111" ];
      description = "DNS servers to try for resolution (tried in order, first success wins)";
    };

    allowedConnections = lib.mkOption {
      type = lib.types.listOf connectionType;
      default = [ ];
      description = ''
        Outbound connections to allow by hostname. Use host = "*" for
        static port-based rules that don't require DNS resolution.
      '';
      example = [
        { host = "acme.zerossl.com"; ports = [ 443 ]; }
        { host = "dns.quad9.net"; ports = [ 53 ]; protocol = "udp"; }
        { host = "*"; ports = [ 25 ]; }
      ];
    };

    updateInterval = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = "How often to re-resolve hostnames (systemd time format)";
    };

    table = lib.mkOption {
      type = lib.types.str;
      default = "filter-output";
      description = "nftables table name containing the output chain";
    };

    chain = lib.mkOption {
      type = lib.types.str;
      default = "output";
      description = "nftables chain where dynamic rules are inserted";
    };

    interfaceMatch = lib.mkOption {
      type = lib.types.str;
      default = ''{ "eth*", "enp*", "ens*", "enx*" }'';
      description = "nftables oifname match expression for external interfaces";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.allowedConnections != [ ];
        message = "foundrix.services.nftables-dns: enable is true but no allowedConnections are configured";
      }
    ];

    networking.nftables.enable = lib.mkDefault true;

    systemd.services.nftables-dns-update = {
      description = "Update nftables sets with DNS-resolved IPs";
      after = [ "nftables.service" ];
      wants = [ "nftables.service" ];
      partOf = [ "nftables.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe (pkgs.python3.withPackages (ps: [ ps.nftables ]))} ${./nftables-dns-update.py} ${configJson}";
      };
    };

    systemd.timers.nftables-dns-update = {
      description = "Periodic nftables DNS resolution";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.updateInterval;
        Unit = "nftables-dns-update.service";
      };
    };
  };
}

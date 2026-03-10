{
  config,
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;
  dnsCfg = config.foundrix.services.nftables-dns;
  hasDns = dnsCfg.enable;
  iface = cfg.interfaceMatch;

  wildcardConnections = lib.optionals hasDns (
    builtins.filter (c: c.host == "*") dnsCfg.allowedConnections
  );
in
{
  options = namespaced __curPos {
    enable = lib.mkEnableOption "controlled egress firewall (default-deny outbound on external interfaces)";

    interfaceMatch = lib.mkOption {
      type = lib.types.str;
      default = ''{ "eth*", "enp*", "ens*", "enx*" }'';
      description = "nftables oifname match expression for external interfaces";
    };

    allowLinkLocalMetadata = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow outbound to 169.254.169.254 (cloud metadata service)";
    };

    extraOutputRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra nftables rules inserted in the output chain before the drop rule";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.enable = true;
    networking.nftables.enable = true;

    # Sync interfaceMatch with nftables-dns if both are active
    foundrix.services.nftables-dns.interfaceMatch = lib.mkIf hasDns (lib.mkDefault cfg.interfaceMatch);

    networking.nftables.tables.filter-output = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority -1; policy accept;

          iifname "lo" accept
          ip6 nexthdr icmpv6 icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert, nd-router-solicit } accept
          ct state vmap { invalid : drop, established : accept, related : accept, new : jump input-allow }
        }

        chain input-allow {
          tcp dport { ${
            lib.concatMapStringsSep ", " toString config.networking.firewall.allowedTCPPorts
          } } accept
          udp dport { ${
            lib.concatMapStringsSep ", " toString config.networking.firewall.allowedUDPPorts
          } } accept
        }

        chain output {
          type filter hook output priority -1; policy accept;

          ct state vmap { established : accept, related : accept, invalid : drop }
          oifname "lo" accept

          oifname ${iface} ip6 nexthdr icmpv6 icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert, nd-router-solicit } accept

          ${lib.optionalString cfg.allowLinkLocalMetadata ''
            ip daddr 169.254.169.254 tcp dport 80 accept
          ''}

          ${lib.optionalString hasDns (lib.concatMapStringsSep "\n          " (server:
            let fam = if lib.hasInfix ":" server then "ip6" else "ip"; in
            "oifname ${iface} ${fam} daddr ${server} udp dport 53 accept"
          ) dnsCfg.dnsServers)}

          oifname ${iface} tcp sport { ${
            lib.concatMapStringsSep ", " toString config.networking.firewall.allowedTCPPorts
          } } ct state new accept

          ${lib.concatMapStringsSep "\n          " (conn:
            let ports = lib.concatMapStringsSep ", " toString conn.ports; in
            "oifname ${iface} ${conn.protocol} dport { ${ports} } accept"
          ) wildcardConnections}

          ${cfg.extraOutputRules}

          oifname ${iface} drop
        }
      '';
    };
  };
}

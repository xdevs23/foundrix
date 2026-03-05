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
        description = "Hostname to resolve";
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

  # Script fragment: resolve A/AAAA records for all hosts of a given protocol,
  # populating associative arrays ${proto}_ipv4_ports / ${proto}_ipv6_ports.
  mkResolveScript = proto: ''
    declare -A ${proto}_ipv4_ports
    declare -A ${proto}_ipv6_ports
    for host in "''${!host_${proto}_ports[@]}"; do
      echo "Resolving $host (${proto}) via ${cfg.dnsServer}..."
      host_has_ips=0

      for ip in $(${lib.getExe' pkgs.dnsutils "dig"} @${cfg.dnsServer} +short +time=5 +tries=2 "$host" A | ${lib.getExe' pkgs.gnused "sed"} '/\.$/d'); do
        echo "  IPv4: $ip (ports: ''${host_${proto}_ports[$host]})"
        if [ -z "''${${proto}_ipv4_ports[$ip]:-}" ]; then
          ${proto}_ipv4_ports[$ip]="''${host_${proto}_ports[$host]}"
        else
          ${proto}_ipv4_ports[$ip]="''${${proto}_ipv4_ports[$ip]},''${host_${proto}_ports[$host]}"
        fi
        host_has_ips=1
      done

      for ip in $(${lib.getExe' pkgs.dnsutils "dig"} @${cfg.dnsServer} +short +time=5 +tries=2 "$host" AAAA | ${lib.getExe' pkgs.gnused "sed"} '/\.$/d'); do
        echo "  IPv6: $ip (ports: ''${host_${proto}_ports[$host]})"
        if [ -z "''${${proto}_ipv6_ports[$ip]:-}" ]; then
          ${proto}_ipv6_ports[$ip]="''${host_${proto}_ports[$host]}"
        else
          ${proto}_ipv6_ports[$ip]="''${${proto}_ipv6_ports[$ip]},''${host_${proto}_ports[$host]}"
        fi
        host_has_ips=1
      done

      if [ $host_has_ips -eq 0 ]; then
        echo "  WARNING: No IP addresses found for $host" >&2
      fi
    done
  '';

  # Script fragment: create nftables sets from the resolved IPs and atomically
  # swap them into the output chain, inserting rules before the drop rule.
  mkSetUpdateScript = proto: ''
    ${proto}_ipv4_count=''${#${proto}_ipv4_ports[@]}
    ${proto}_ipv6_count=''${#${proto}_ipv6_ports[@]}

    if [ ''$${proto}_ipv4_count -eq 0 ] && [ ''$${proto}_ipv6_count -eq 0 ]; then
      echo "No ${proto} IPs resolved, skipping"
    else
      ${proto}_set_hash=$(
        (
          [ ''$${proto}_ipv4_count -gt 0 ] && printf '${proto}_v4:%s:%s\n' "''${!${proto}_ipv4_ports[@]}" "''${${proto}_ipv4_ports[@]}"
          [ ''$${proto}_ipv6_count -gt 0 ] && printf '${proto}_v6:%s:%s\n' "''${!${proto}_ipv6_ports[@]}" "''${${proto}_ipv6_ports[@]}"
          true
        ) | sort -u | ${lib.getExe' pkgs.coreutils "sha256sum"} | cut -c1-8
      )
      new_${proto}_set_v4="allowed_dynamic_${proto}_ipv4_''$${proto}_set_hash"
      new_${proto}_set_v6="allowed_dynamic_${proto}_ipv6_''$${proto}_set_hash"

      nft=${lib.getExe pkgs.nftables}

      cat > /tmp/nftables-dns-update-${proto}.nft <<EOF
    table inet ${cfg.table} {
      set ''$new_${proto}_set_v4 {
        type ipv4_addr . inet_service
        flags interval
      }
      set ''$new_${proto}_set_v6 {
        type ipv6_addr . inet_service
        flags interval
      }
    }
    EOF

      if [ ''$${proto}_ipv4_count -gt 0 ]; then
        for ip in "''${!${proto}_ipv4_ports[@]}"; do
          IFS=',' read -ra ports <<< "''${${proto}_ipv4_ports[''$ip]}"
          for port in "''${ports[@]}"; do
            echo "add element inet ${cfg.table} ''$new_${proto}_set_v4 { ''$ip . ''$port }" >> /tmp/nftables-dns-update-${proto}.nft
          done
        done
      fi

      if [ ''$${proto}_ipv6_count -gt 0 ]; then
        for ip in "''${!${proto}_ipv6_ports[@]}"; do
          IFS=',' read -ra ports <<< "''${${proto}_ipv6_ports[''$ip]}"
          for port in "''${ports[@]}"; do
            echo "add element inet ${cfg.table} ''$new_${proto}_set_v6 { ''$ip . ''$port }" >> /tmp/nftables-dns-update-${proto}.nft
          done
        done
      fi

      $nft -f /tmp/nftables-dns-update-${proto}.nft

      old_${proto}_set_v4=$($nft -a list chain inet ${cfg.table} ${cfg.chain} 2>/dev/null | \
        grep -oP 'allowed_dynamic_${proto}_ipv4_\w+' | head -1 || echo "")
      old_${proto}_set_v6=$($nft -a list chain inet ${cfg.table} ${cfg.chain} 2>/dev/null | \
        grep -oP 'allowed_dynamic_${proto}_ipv6_\w+' | head -1 || echo "")
      drop_handle=$($nft -a list chain inet ${cfg.table} ${cfg.chain} 2>/dev/null | \
        grep 'oifname.*drop' | grep -oP 'handle \K\d+' || echo "")

      if [ -n "''$drop_handle" ]; then
        iface_match='${cfg.interfaceMatch}'

        if [ ''$${proto}_ipv4_count -gt 0 ]; then
          $nft insert rule inet ${cfg.table} ${cfg.chain} position ''$drop_handle \
            oifname "$iface_match" ip daddr . ${proto} dport @''$new_${proto}_set_v4 accept
        fi

        if [ ''$${proto}_ipv6_count -gt 0 ]; then
          $nft insert rule inet ${cfg.table} ${cfg.chain} position ''$drop_handle \
            oifname "$iface_match" ip6 daddr . ${proto} dport @''$new_${proto}_set_v6 accept
        fi
      fi

      if [ -n "''$old_${proto}_set_v4" ] && [ "''$old_${proto}_set_v4" != "''$new_${proto}_set_v4" ]; then
        $nft delete rule inet ${cfg.table} ${cfg.chain} \
          oifname "$iface_match" ip daddr . ${proto} dport @''$old_${proto}_set_v4 accept 2>/dev/null || true
        $nft delete set inet ${cfg.table} ''$old_${proto}_set_v4 2>/dev/null || true
      fi

      if [ -n "''$old_${proto}_set_v6" ] && [ "''$old_${proto}_set_v6" != "''$new_${proto}_set_v6" ]; then
        $nft delete rule inet ${cfg.table} ${cfg.chain} \
          oifname "$iface_match" ip6 daddr . ${proto} dport @''$old_${proto}_set_v6 accept 2>/dev/null || true
        $nft delete set inet ${cfg.table} ''$old_${proto}_set_v6 2>/dev/null || true
      fi

      echo "${proto}: IPv4 ''$${proto}_ipv4_count IPs, IPv6 ''$${proto}_ipv6_count IPs"
      rm -f /tmp/nftables-dns-update-${proto}.nft
    fi
  '';
in
{
  options = namespaced __curPos {
    enable = lib.mkEnableOption "dynamic DNS resolution for nftables outbound rules";

    dnsServer = lib.mkOption {
      type = lib.types.str;
      default = "1.1.1.1";
      description = "DNS server address used for resolution";
      example = "2606:4700:4700::1111";
    };

    allowedConnections = lib.mkOption {
      type = lib.types.listOf connectionType;
      default = [ ];
      description = "Outbound connections to allow by hostname";
      example = [
        { host = "acme.zerossl.com"; ports = [ 443 ]; }
        { host = "dns.quad9.net"; ports = [ 53 ]; protocol = "udp"; }
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
        ExecStart = pkgs.writeShellScript "nftables-dns-update" ''
          set -euo pipefail

          declare -A host_tcp_ports
          declare -A host_udp_ports
          ${lib.concatMapStringsSep "\n" (
            conn:
            if conn.protocol == "tcp" then
              ''host_tcp_ports["${conn.host}"]="${lib.concatMapStringsSep "," toString conn.ports}"''
            else
              ''host_udp_ports["${conn.host}"]="${lib.concatMapStringsSep "," toString conn.ports}"''
          ) cfg.allowedConnections}

          ${mkResolveScript "tcp"}
          ${mkResolveScript "udp"}

          ${mkSetUpdateScript "tcp"}
          ${mkSetUpdateScript "udp"}

          echo "DNS update complete"
        '';
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

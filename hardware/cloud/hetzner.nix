{
  config,
  lib,
  pkgs,
  modulesPath,
  foundrixModules,
  traitTypes,
  ...
}:
let
  # Repart-driven online growth only makes sense when repart owns the data
  # volume. With the LUKS manager as provisioner there are no repart.d
  # definitions and growth is a manual crypt-aware procedure (see
  # docs/var-luks.md) — the trait tells us without coupling to the module.
  varProvisioner = config.foundrix.traits.filesystem.varProvisioner or null;
  repartResize = varProvisioner != traitTypes.filesystem.varProvisioner.luks-manager;
in
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
    foundrixModules.config.image.boot.systemd-boot-bios
    foundrixModules.config.runtime.repart.main
  ];

  services.cloud-init.enable = false;

  # The OS disk is /dev/sda on Hetzner Cloud. Growing the main partition to
  # the disk's size is boot-time work (see runtime/repart/main.nix) — the
  # online-resize service below only reacts to disks that change size while
  # the system runs, which the OS disk never does. Read-only store layouts
  # have no main partition to grow, so they opt out by trait.
  foundrix.config.runtime.repart.main.disk = lib.mkDefault (
    if (config.foundrix.traits.filesystem.readOnlyStore or null) == true then null else "/dev/sda"
  );

  # Online disk resize: detect capacity changes and grow filesystem
  services.udev.extraRules = lib.mkIf repartResize ''
    ACTION=="change", SUBSYSTEM=="block", ENV{RESIZE}=="1", ENV{DEVTYPE}=="disk", TAG+="systemd", ENV{SYSTEMD_WANTS}="disk-online-resize@%k.service"
  '';

  systemd.services."disk-online-resize@" = lib.mkIf repartResize {
    description = "Online resize for /dev/%i";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "disk-online-resize" ''
        disk="/dev/$1"

        echo "Disk $disk resized, running repart..."
        ${pkgs.systemd}/bin/systemd-repart --dry-run=no "$disk"

        part=$(${pkgs.util-linux}/bin/lsblk -ln -o NAME "$disk" | tail -1)
        mountpoint=$(${pkgs.util-linux}/bin/findmnt -n -o TARGET "/dev/$part" 2>/dev/null)

        if [ -z "$mountpoint" ]; then
          echo "No mountpoint found for /dev/$part, skipping resize" >&2
          exit 0
        fi

        unit="systemd-growfs@$(systemd-escape --path "$mountpoint").service"
        echo "Growing filesystem at $mountpoint"
        systemctl restart "$unit"
      ''} %i";
    };
  };

  # Use systemd-networkd instead of legacy dhcpcd
  networking.useDHCP = false;
  systemd.network.enable = true;
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "ipv4";
    linkConfig.RequiredForOnline = "routable";
  };

  # Hetzner doesn't use SLAAC — read IPv6 from metadata and configure statically
  systemd.services.hetzner-ipv6 = {
    description = "Configure IPv6 from Hetzner metadata";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "hetzner-ipv6" ''
        metadata=$(${lib.getExe pkgs.curl} -sf http://169.254.169.254/hetzner/v1/metadata)

        ipv6_subnet=$(echo "$metadata" | ${lib.getExe pkgs.yq} -r '.["network-config"].config[0].subnets[] | select(.ipv6 == true)')
        addr=$(echo "$ipv6_subnet" | ${lib.getExe pkgs.yq} -r '.address')
        gw=$(echo "$ipv6_subnet" | ${lib.getExe pkgs.yq} -r '.gateway')

        if [ -z "$addr" ] || [ "$addr" = "null" ]; then
          echo "No IPv6 address found in metadata" >&2
          exit 1
        fi

        iface=$(${lib.getExe' pkgs.iproute2 "ip"} -o link show | ${lib.getExe pkgs.gawk} -F': ' '/state UP/ && /en/ {print $2; exit}')

        echo "Configuring $addr on $iface (gateway $gw)"
        ${lib.getExe' pkgs.iproute2 "ip"} -6 addr replace "$addr" dev "$iface"
        ${lib.getExe' pkgs.iproute2 "ip"} -6 route replace default via "$gw" dev "$iface"
      '';
    };
  };

  # Override DHCP-provided DNS with configured nameservers
  systemd.services.enforce-dns-config = {
    description = "Enforce preferred DNS configuration";
    requires = [ "systemd-resolved.service" ];
    after = [
      "systemd-resolved.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "enforce-dns" ''
        iface=$(${lib.getExe' pkgs.iproute2 "ip"} -o link show | ${lib.getExe pkgs.gawk} -F': ' '/state UP/ && /en/ {print $2; exit}')

        if [ -z "$iface" ]; then
          echo "No active en* interface found" >&2
          exit 1
        fi

        echo "Setting DNS on interface: $iface"
        ${pkgs.systemd}/bin/resolvectl dns "$iface" ${
          lib.concatStringsSep " " (
            config.networking.nameservers ++ (config.services.resolved.settings.Resolve.FallbackDNS or [ ])
          )
        }
        ${pkgs.systemd}/bin/resolvectl default-route "$iface" yes

        echo "DNS configuration enforced: ${lib.concatStringsSep ", " config.networking.nameservers}"
      '';
    };
  };

  # systemd-repart re-reads the partition table, which causes udev to recreate
  # /dev/disk/by-partuuid/* symlinks. Ensure /var waits for udev to settle.
  fileSystems."/var".options = [ "x-systemd.after=initrd-parse-etc.service" ];
}

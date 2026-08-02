# SSH access to the systemd initrd — remote debugging of any stage-1
# problem, and the passphrase channel for encrypted-volume setups
# (config/filesystem/var-luks.nix sets the login shell to its TUI).
#
# A thin, opinionated layer over the nixpkgs `boot.initrd.network.ssh`
# module, which keeps owning sshd itself. What nixpkgs does not offer
# (verified against 26.05: no runtime key generation or persistence):
#
#  - A dedicated port + host key, so clients never get host-key-changed
#    warnings against the main sshd. The key is generated inside the
#    initrd on first boot and persisted on the ESP — never in the nix
#    store or git. (It cannot be more secret than the unencrypted disk it
#    sits on; its job is stable identity, not secrecy.)
#  - networkd defaults in the initrd (DHCPv4 on en*), overridable via
#    `boot.initrd.systemd.network.networks`.
#  - A configurable login shell for interactive sessions.
#
# Authorized keys follow the nixpkgs default: root's main-system keys.
{
  config,
  lib,
  pkgs,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    port = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Port for the initrd sshd (kept off 22 to separate host-key identities)";
    };

    loginShell = lib.mkOption {
      type = lib.types.str;
      default = "/bin/sh";
      description = "Login shell for interactive initrd SSH sessions";
    };

    hostKeyDir = lib.mkOption {
      type = lib.types.str;
      default = "initrd-ssh";
      description = "Directory on the ESP holding the persisted host key";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      # Locate the ESP the way the esp filesystem module does, degrading to
      # the ESP type GUID (which foundrix images also use as the PARTUUID).
      espDevice =
        (config.foundrix.config.filesystem.esp or { }).device
          or "PARTUUID=c12a7328-f81f-11d2-ba4b-00a0c93ec93b";
      # fstab spec-style device strings resolve to their udev symlink; an
      # unrecognized shape must fail the eval rather than silently landing
      # in the volatile-host-key fallback on every boot.
      specPrefixes = {
        "PARTUUID=" = "/dev/disk/by-partuuid/";
        "UUID=" = "/dev/disk/by-uuid/";
        "LABEL=" = "/dev/disk/by-label/";
        "PARTLABEL=" = "/dev/disk/by-partlabel/";
      };
      matchedPrefix = lib.findFirst (p: lib.hasPrefix p espDevice) null (builtins.attrNames specPrefixes);
      espBlockDev =
        if matchedPrefix != null then
          specPrefixes.${matchedPrefix} + lib.toLower (lib.removePrefix matchedPrefix espDevice)
        else if lib.hasPrefix "/" espDevice then
          espDevice
        else
          throw "initrd.ssh: unsupported ESP device string `${espDevice}` (expected PARTUUID=/UUID=/LABEL=/PARTLABEL= or an absolute path)";
    in
    {
      # Network in the initrd: DHCPv4 on en*, mirroring common server setups.
      boot.initrd.network.enable = true;
      boot.initrd.systemd.network.networks."10-wan" = {
        matchConfig.Name = lib.mkDefault "en*";
        networkConfig.DHCP = lib.mkDefault "ipv4";
        linkConfig.RequiredForOnline = lib.mkDefault "routable";
      };

      boot.initrd.network.ssh = {
        enable = true;
        port = cfg.port;
        # Host key is provisioned at runtime from the ESP (see below), not
        # baked into the initrd.
        ignoreEmptyHostKeys = true;
      };

      boot.initrd.systemd.users.root.shell = cfg.loginShell;

      # Mounting the vfat ESP inside the initrd.
      boot.initrd.availableKernelModules = [
        "vfat"
        "nls_cp437"
        "nls_iso8859-1"
      ];

      boot.initrd.systemd.extraBin = {
        ssh-keygen = lib.getExe' config.programs.ssh.package "ssh-keygen";
        # Debugging quality-of-life for interactive initrd SSH sessions.
        grep = lib.getExe pkgs.gnugrep;
        sed = lib.getExe pkgs.gnused;
      };

      # sshd has no HostKey directive (hostKeys = []), so it falls back to
      # the compiled-in default path /etc/ssh/ssh_host_ed25519_key. This
      # oneshot puts the ESP-persisted key there before sshd starts,
      # generating it on first boot.
      boot.initrd.systemd.services.initrd-ssh-host-key = {
        description = "Provision initrd SSH host key from the ESP";
        before = [ "sshd.service" ];
        requiredBy = [ "sshd.service" ];
        unitConfig = {
          DefaultDependencies = false;
          RequiresMountsFor = "/run";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          esp=${espBlockDev}
          key=/etc/ssh/ssh_host_ed25519_key

          # The ESP device is on the boot disk; give udev a moment on slow
          # boots.
          for _ in $(seq 60); do
            [ -b "$esp" ] && break
            sleep 0.5
          done
          if ! [ -b "$esp" ]; then
            echo "ESP $esp did not appear; generating a volatile host key" >&2
            ssh-keygen -t ed25519 -N "" -f "$key"
            exit 0
          fi

          mkdir -p /esp /etc/ssh
          # A corrupt-but-present ESP must not take sshd down with it (this
          # service is a hard requirement of sshd): fall back to a volatile
          # key.
          if ! mount -t vfat "$esp" /esp; then
            echo "mounting ESP failed; generating a volatile host key" >&2
            ssh-keygen -t ed25519 -N "" -f "$key"
            exit 0
          fi
          trap 'umount /esp' EXIT

          if [ -s /esp/${cfg.hostKeyDir}/ssh_host_ed25519_key ]; then
            cp /esp/${cfg.hostKeyDir}/ssh_host_ed25519_key "$key"
          else
            ssh-keygen -t ed25519 -N "" -f "$key"
            mkdir -p /esp/${cfg.hostKeyDir}
            cp "$key" /esp/${cfg.hostKeyDir}/ssh_host_ed25519_key
          fi
          chmod 0600 "$key"

          # Log the fingerprint at debug level: visible in dmesg/journal
          # without writing over any console UI.
          fp=$(ssh-keygen -lf "$key")
          echo "<7>initrd SSH host key: $fp" > /dev/kmsg || true
        '';
      };
    };
}

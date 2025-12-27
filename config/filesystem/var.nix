{
  lib,
  pkgs,
  namespaced,
  namespacedCfg,
  ...
}:
let
  machineIdCreate = pkgs.writeShellScriptBin "machine-id-create" ''
    set -euo pipefail
    target="/sysroot/var/etc/machine-id"
    mkdir -p "$(dirname "$target")"
    if [ ! -f "$target" ]; then
      head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$target"
      echo "" >> "$target"
    fi
    [ -s "$target" ] || { echo "FATAL: machine-id missing or empty" >&2; exit 1; }
  '';
in
{
  options = namespaced __curPos {
    device = lib.mkOption {
      type = lib.types.str;
      default = "PARTLABEL=nixos";
      description = "Device path for /var mount";
    };
    fsType = lib.mkOption {
      type = lib.types.str;
      default = "btrfs";
      description = "Filesystem type for /var";
    };
    fsOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        if (namespacedCfg __curPos).fsType == "btrfs" then
          [
            "subvol=@var"
            "compress=lzo"
          ]
        else
          [ ];
      description = "Mount options for /var";
    };
    persistMachineId = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Persist machine-id to /var/etc/machine-id and create it in initrd.
        Required for DHCP client when using tmpfs root.
        Implies neededForBoot.
      '';
    };
    persistSshHostKeys = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Persist SSH host keys to /var/etc/ssh";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    lib.mkMerge [
      {
        fileSystems."/var" = {
          device = cfg.device;
          fsType = cfg.fsType;
          options = cfg.fsOptions ++ [ "noatime" ];
          neededForBoot = cfg.persistMachineId;
        };
      }

      (lib.mkIf cfg.persistMachineId {
        environment.etc."machine-id".source = "/var/etc/machine-id";

        systemd.tmpfiles.settings."var-etc"."/var/etc".d = {
          mode = "0755";
          user = "0";
          group = "0";
        };

        boot.initrd.systemd.storePaths = [ machineIdCreate ];
        boot.initrd.systemd.services.machine-id-create = {
          wantedBy = [ "initrd.target" ];
          before = [ "initrd.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe machineIdCreate;
          };
          unitConfig = {
            DefaultDependencies = "no";
            RequiresMountsFor = "/sysroot/var";
            OnFailure = "emergency.target";
          };
        };
      })

      (lib.mkIf cfg.persistSshHostKeys {
        environment.etc = {
          "ssh/ssh_host_rsa_key".source = "/var/etc/ssh/ssh_host_rsa_key";
          "ssh/ssh_host_rsa_key.pub".source = "/var/etc/ssh/ssh_host_rsa_key.pub";
          "ssh/ssh_host_ed25519_key".source = "/var/etc/ssh/ssh_host_ed25519_key";
          "ssh/ssh_host_ed25519_key.pub".source = "/var/etc/ssh/ssh_host_ed25519_key.pub";
        };

        systemd.tmpfiles.settings."var-etc-ssh"."/var/etc/ssh".d = {
          mode = "0755";
          user = "0";
          group = "0";
        };
      })
    ];
}

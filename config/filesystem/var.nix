{
  config,
  lib,
  pkgs,
  namespaced,
  namespacedCfg,
  traitTypes,
  ...
}:
let
  # Check volatile root trait (graceful non-existence)
  rootType = config.foundrix.traits.filesystem.rootType or null;
  isVolatileRoot = rootType == traitTypes.filesystem.rootType.volatile;

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
      default = isVolatileRoot;
      description = ''
        Persist machine-id to /var/etc/machine-id and create it in initrd.
        Required for DHCP client when using tmpfs root.
        Implies neededForBoot.
        Auto-enabled when foundrix.traits.filesystem.rootType is volatile.
      '';
    };
    persistSshHostKeys = lib.mkOption {
      type = lib.types.bool;
      default = isVolatileRoot;
      description = ''
        Persist SSH host keys to /var/etc/ssh.
        Auto-enabled when foundrix.traits.filesystem.rootType is volatile.
      '';
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

        systemd.services.systemd-machine-id-commit.enable = false;

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
        services.openssh.hostKeys = lib.mkForce [
          {
            type = "rsa";
            bits = 4096;
            path = "/var/etc/ssh/ssh_host_rsa_key";
          }
          {
            type = "ed25519";
            path = "/var/etc/ssh/ssh_host_ed25519_key";
          }
        ];

        systemd.tmpfiles.settings."var-etc-ssh"."/var/etc/ssh".d = {
          mode = "0755";
          user = "0";
          group = "0";
        };
      })
    ];
}

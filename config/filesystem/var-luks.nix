# /var on LUKS2-encrypted btrfs, managed by var-disk-manager
# (packages/var-disk-manager): a Rust initrd daemon that classifies the
# glob-selected data volumes by CONTENT (never attach order) and acts:
#
#   LUKS only        -> ask passphrase (TUI on console + SSH), open, boot.
#   legacy only      -> boot unencrypted (pre-migration compatibility).
#   legacy + blank   -> MIGRATE (btrfs send/receive), then BLOCK.
#   legacy + LUKS    -> BLOCK boot; never run off the unencrypted disk again.
#   blank only       -> fresh provisioning; servers are born encrypted.
#
# "legacy" is a btrfs partition carrying the discoverable-partitions var
# type GUID as its PARTUUID (what runtime.repart.var creates); "blank"
# means zero signatures and zero partition table — the only thing the
# manager will ever write to.
#
# /var mounts by btrfs FILESYSTEM label: carried by the fs whether it sits
# on a plain partition or inside the LUKS mapper — one fstab entry for
# every phase. The passphrase is entered on the machine console or over
# initrd SSH (config/initrd/ssh.nix, imported here; the login shell IS the
# manager's TUI). See docs/var-luks.md for the operator flow.
#
# Announces foundrix.traits.filesystem.varProvisioner = luks-manager:
# importing this together with runtime.repart.var fails eval by enum
# conflict — repart would format the blank migration target unencrypted.
{
  config,
  lib,
  pkgs,
  namespaced,
  namespacedCfg,
  foundrixModules,
  traitTypes,
  ...
}:
{
  imports = [
    foundrixModules.config.filesystem.var
    foundrixModules.config.initrd.ssh
  ];

  options = namespaced __curPos {
    volumeGlob = lib.mkOption {
      type = lib.types.str;
      example = "/dev/disk/by-id/scsi-0HC_Volume_*";
      description = ''
        Glob selecting the data volumes' whole-disk by-id links. Must have
        the form <dir>/<prefix>* (the daemon supports no other wildcards);
        partition links are skipped automatically. Typically set by the
        device configuration.
      '';
    };

    luksPartUuid = lib.mkOption {
      type = lib.types.str;
      default = "cab17794-a0a1-4908-8dd2-3f205a938611";
      description = ''
        PARTUUID the manager assigns to (and requires of) the LUKS
        partition. A stable handle, not a secret — identity is
        content-based; the default is fine unless it collides with
        something in your fleet.
      '';
    };

    fsLabel = lib.mkOption {
      type = lib.types.str;
      default = "var";
      description = "btrfs filesystem label /var is mounted by";
    };

    mapperName = lib.mkOption {
      type = lib.types.str;
      default = "var";
      description = "dm mapper name for the opened LUKS volume";
    };

    minPassphraseLength = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
      description = "Minimum passphrase length enforced at creation time";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      varDiskManager = pkgs.callPackage ../../packages/var-disk-manager { };
      daemonArgs = lib.escapeShellArgs [
        "--volume-glob"
        cfg.volumeGlob
        "--luks-partuuid"
        cfg.luksPartUuid
        "--fs-label"
        cfg.fsLabel
        "--mapper"
        cfg.mapperName
        "--min-passphrase-len"
        (toString cfg.minPassphraseLength)
      ];
    in
    {
      # Mutual exclusion with the repart provisioners falls out of the enum:
      # importing runtime.repart.var or .data alongside this module fails
      # eval with a definition conflict on this trait. Initrd repart in
      # general stays available for OTHER partitions — but never point
      # repart definitions at the data volumes: it would format the blank
      # migration target as an unencrypted partition.
      foundrix.traits.filesystem.varProvisioner = traitTypes.filesystem.varProvisioner.luks-manager;

      assertions = [
        {
          assertion = config.boot.initrd.systemd.enable;
          message = "filesystem.var-luks requires the systemd-based initrd (boot.initrd.systemd.enable)";
        }
        {
          # Forces the trait merge early, so a competing provisioner
          # surfaces as the trait's definition conflict rather than as
          # whichever downstream option happens to collide first.
          assertion =
            config.foundrix.traits.filesystem.varProvisioner
            == traitTypes.filesystem.varProvisioner.luks-manager;
          message = "filesystem.var-luks: another module owns /var provisioning (varProvisioner trait)";
        }
      ];

      # Interactive initrd logins land in the manager's TUI (same screen as
      # the console; Esc/Ctrl-C drops to a shell, `ssh host <cmd>` passes
      # through to /bin/sh).
      foundrix.config.initrd.ssh.loginShell = lib.mkDefault (
        lib.getExe' varDiskManager "var-disk-manager-tui"
      );

      # One fstab entry for all phases; the device appears once the manager
      # has labeled (legacy), unlocked (steady state) or created (fresh) the
      # fs. device-timeout=infinity: passphrase entry takes as long as it
      # takes; the same option rides into the main system's fstab, where a
      # lost device also hangs the mount forever instead of failing —
      # accepted, see docs/var-luks.md.
      foundrix.config.filesystem.var = {
        device = lib.mkDefault "/dev/disk/by-label/${cfg.fsLabel}";
        fsOptions = lib.mkDefault [
          "subvol=var"
          "x-systemd.device-timeout=infinity"
        ];
      };

      # The fstab-generated mount must not race the manager: in the migrate
      # and block states the legacy fs already carries the label, so the
      # device is mountable before the manager has decided anything.
      # Requires+After keeps /sysroot/var unmounted until the manager
      # approves the boot (and forever in the deliberately-blocked states).
      # Initrd-only drop-in: the unit does not exist in the main system.
      boot.initrd.systemd.units."sysroot-var.mount" = {
        overrideStrategy = "asDropin";
        text = ''
          [Unit]
          Requires=var-disk-manager.service
          After=var-disk-manager.service
        '';
      };

      # dm-crypt is not hardware, so nothing (no udev modalias) ever loads it
      # or its ciphers on demand. These must be BOTH present in the initrd and
      # force-loaded — see kernelModules below.
      #
      # The full set, and why each is needed (Linux 7.x):
      #   dm_mod, dm_crypt   the device-mapper target itself
      #   aes, xts, ecb      the LUKS2 cipher spec aes-xts-plain64 (xts wraps ecb(aes))
      #   cbc                dm-crypt links encrypted-keys, whose module init does
      #                      crypto_alloc_skcipher("cbc(aes)") and FAILS the whole
      #                      load with "encrypted_key: failed to alloc_cipher (-2)"
      #                      if cbc(aes) can't be built. cbc is a SEPARATE module in
      #                      7.x (CRYPTO_CBC=m, selected by DM_CRYPT=m), and a
      #                      crypto-API request like "cbc(aes)" leaves NO modules.dep
      #                      edge, so the initrd closure builder NEVER pulls cbc.ko
      #                      in — it must be named explicitly. This was the root
      #                      cause of "crypt: unknown target type" on 7.1.3.
      #   sha256             LUKS2 key derivation
      boot.initrd.availableKernelModules = [
        "dm_mod"
        "dm_crypt"
        "aes"
        "xts"
        "ecb"
        "cbc"
        "sha256"
      ];

      # Force-load the same set. availableKernelModules only makes modules
      # available for on-demand (modalias) loading, which never fires for
      # dm-crypt. kernelModules lists them in the initrd's modules-load.d so
      # systemd-modules-load.service loads them at boot — and listing here also
      # adds them to the initrd closure, which is how cbc.ko gets included at
      # all (see above).
      boot.initrd.kernelModules = [
        "dm_mod"
        "dm_crypt"
        "aes"
        "xts"
        "ecb"
        "cbc"
        "sha256"
      ];

      # Tools land in the initrd's /bin — the only reliably-populated
      # location (store paths referenced only inside a program are NOT
      # copied into the initrd by make-initrd-ng). The daemon preflights
      # every tool and fails the boot loudly if one is missing.
      boot.initrd.systemd.extraBin = {
        blkid = lib.getExe' pkgs.util-linux "blkid";
        lsblk = lib.getExe' pkgs.util-linux "lsblk";
        blockdev = lib.getExe' pkgs.util-linux "blockdev";
        wipefs = lib.getExe' pkgs.util-linux "wipefs";
        sgdisk = lib.getExe' pkgs.gptfdisk "sgdisk";
        cryptsetup = lib.getExe' pkgs.cryptsetup "cryptsetup";
        btrfs = lib.getExe' pkgs.btrfs-progs "btrfs";
        "mkfs.btrfs" = lib.getExe' pkgs.btrfs-progs "mkfs.btrfs";
      };

      boot.initrd.supportedFilesystems.btrfs = true;

      boot.initrd.systemd.storePaths = [ varDiskManager ];
      boot.initrd.systemd.services.var-disk-manager = {
        description = "Classify, unlock, migrate or provision the /var data volume";
        wantedBy = [ "initrd.target" ];
        before = [ "initrd.target" ];
        after = [
          "systemd-udev-trigger.service"
          "systemd-udevd.service"
        ];
        wants = [ "systemd-udev-trigger.service" ];
        unitConfig = {
          DefaultDependencies = false;
          OnFailure = "emergency.target";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "infinity";
          # Load the dm-crypt stack in dependency order right before the
          # daemon runs cryptsetup. kernelModules already registers these with
          # systemd-modules-load.service, but this service has
          # DefaultDependencies=false and is only ordered after udev, so it can
          # race modules-load; loading here makes the unlock independent of
          # initrd unit ordering. Order matters: dm-crypt links encrypted-keys,
          # whose init does crypto_alloc_skcipher("cbc(aes)"), so aes+cbc must
          # be registered before dm_crypt. (See the availableKernelModules note
          # above for why cbc is the load-bearing one on 7.x.)
          ExecStartPre =
            let
              modprobe = "/bin/modprobe";
            in
            map (m: "${modprobe} ${m}") [
              "dm_mod"
              "aes"
              "ecb"
              "cbc"
              "xts"
              "sha256"
              "dm_crypt"
            ];
          ExecStart = "${lib.getExe varDiskManager} ${daemonArgs}";
        };
      };

      # Fullscreen TUI on the physical console; renders the same daemon
      # state as SSH sessions, any client can answer the prompt. Runs
      # alongside the oneshot daemon — deliberately NOT ordered After= it
      # (the daemon only "finishes" when it releases the boot).
      boot.initrd.systemd.services.var-disk-manager-console = {
        description = "var-disk-manager console UI";
        wantedBy = [ "initrd.target" ];
        # emergency.target must win the console: sulogin and this TUI
        # cannot share the tty, and the emergency path is when the operator
        # needs a plain shell most.
        conflicts = [
          "shutdown.target"
          "emergency.target"
        ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          # Boot continues in parallel by design, and systemd prints unit
          # status straight onto /dev/console over the TUI. Same remedy as
          # plymouth: SIGRTMIN+21 tells PID 1 to stop console status
          # output, SIGRTMIN+20 re-enables it. ExecStopPost runs on every
          # exit path.
          ExecStartPre = "/bin/kill -s RTMIN+21 1";
          ExecStopPost = "/bin/kill -s RTMIN+20 1";
          # --console: exit (releasing the tty) when the daemon goes away
          # instead of waiting for a keypress.
          ExecStart = "${lib.getExe' varDiskManager "var-disk-manager-tui"} --console";
          Type = "simple";
          Restart = "no";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "journal";
          TTYPath = "/dev/console";
          TTYReset = true;
          TTYVHangup = true;
        };
      };

      # Tell the main system about the mapping so shutdown is ordered
      # correctly (x-initrd.attach: attached in initrd, detached by the
      # initrd shutdown phase). nofail keeps pre-migration boots working
      # while the LUKS volume doesn't exist yet.
      environment.etc.crypttab.text = ''
        ${cfg.mapperName} /dev/disk/by-partuuid/${cfg.luksPartUuid} none luks,discard,x-initrd.attach,nofail
      '';
    };
}

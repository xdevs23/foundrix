# Operator-provided secrets: the half of the secret problem that cannot be
# solved on the host. `services/secrets.nix` GENERATES secrets; this module
# COLLECTS them from a human, blocks the boot until each one is present and
# PROVEN valid, and writes it as an env-file consumers read with
# `EnvironmentFile=`. See docs/operator-secrets.md.
#
# This module is the single source of truth for identity — names, ordered
# field lists, destinations, ownership and the validator argv. It renders
# that into a spec JSON handed to `operator-secretsd` (packages/
# operator-secrets). The spec carries NO secret values, only identity, and
# is therefore safe in the (world-readable) nix store. Values exist only in
# the daemon's memory, on the validator's stdin, and in the destination
# file — never in argv, the environment, the journal or the store.
#
# Boot ordering (docs/operator-secrets.md "Boot ordering"): after sshd and
# the network — the operator must be able to SSH in to answer, and the
# validator needs the network to reach its dependency — and before
# multi-user.target, so the boot visibly waits. Consumers listed in
# `requiredBy` additionally get Requires=/After= via the daemon's [Install]
# section, exactly as services/secrets.nix wires its generators.
{
  lib,
  pkgs,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;

  fieldType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Human-readable hint shown next to the field in the TUI";
      };

      sensitive = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether the TUI masks this field's echo and refuses to pre-fill it
          into a re-prompt. It is NOT a confidentiality boundary: every field
          of a secret lands in the same file with the same mode.
        '';
      };

      order = lib.mkOption {
        type = lib.types.int;
        default = 1000;
        description = ''
          Sort key deciding the order the operator is asked for the fields
          in, and the order of the `KEY=VALUE` lines in the output file.

          An attrset has no meaningful order of its own, so ordering is made
          explicit here: fields are sorted by `order`, ties broken by field
          name. Leaving every `order` at its default therefore yields a
          stable alphabetical order; set it only when the prompt should
          deviate from that (e.g. an identifier before its secret).
        '';
      };
    };
  };

  secretType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        description = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "What this secret is and where the operator obtains it";
        };

        fields = lib.mkOption {
          type = lib.types.attrsOf fieldType;
          description = ''
            Env-file keys making up this secret. Presented to the operator
            and written to the file in `order` (see the `order` option).
          '';
          example = lib.literalExpression ''
            {
              CLIENT_ID = { order = 10; };
              CLIENT_SECRET = { order = 20; sensitive = true; };
            }
          '';
        };

        validateCommand = lib.mkOption {
          type = lib.types.nullOr (lib.types.nonEmptyListOf lib.types.str);
          default = null;
          description = ''
            argv of the validator: program path followed by its flags. A
            LIST, never a shell string — no shell is involved in spawning
            it, so the values can never be word-split or interpreted.

            The daemon writes `{"fields":{...}}` to its stdin and reads
            `{"status":"valid"|"invalid"|"error"}` from its stdout; `status`
            is authoritative, not the exit code, and a validator that
            crashes or prints garbage counts as `error` — which never
            discards or rewrites a stored secret.

            `null` means the secret has no external proof: all declared
            fields present and non-empty is the acceptance criterion. Use a
            real validator whenever one is possible (e.g. OIDC credentials
            can be proven against the issuer) — presence-only acceptance
            catches typos in field names, not wrong values.
          '';
          # foundrixPkgs does NOT expose the directory-based packages:
          # packagesFromDirectoryRecursive keys on `package.nix` and these
          # use `default.nix`, so the name would resolve to a scope and
          # `lib.getExe` would fail eval. Reach it by path, as
          # config/filesystem/var-luks.nix does for var-disk-manager.
          example = lib.literalExpression ''
            let
              validator = pkgs.callPackage (foundrix + "/packages/oidc-credential-validator") { };
            in
            [ (lib.getExe validator) "--issuer" "https://sso.example.com" ]
          '';
        };

        path = lib.mkOption {
          type = lib.types.str;
          default = "/var/credentials/${name}.env";
          defaultText = lib.literalExpression ''"/var/credentials/''${name}.env"'';
          description = ''
            Destination env-file. Must live on persistent storage the host
            considers safe at rest — the threat model assumes `/var` on LUKS
            (config/filesystem/var-luks.nix).
          '';
        };

        owner = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = "User who owns the secret file";
        };

        group = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Group for the secret file. Defaults to owner's primary group.";
        };

        mode = lib.mkOption {
          type = lib.types.str;
          default = "0400";
          description = "File permissions for the secret";
        };

        requiredBy = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Systemd units that must not start before this secret exists.
            They get Requires= and After= on the collector, so a missing or
            unprovable credential blocks loudly instead of leaving a unit
            silently not started.
          '';
          example = [ "forgejo.service" ];
        };
      };
    }
  );

  # An attrset gives no order, so derive one explicitly: by `order`, ties
  # broken by name. Total (names are unique), hence deterministic.
  orderedFields =
    fields:
    map (f: { inherit (f) name description sensitive; }) (
      lib.sort (a: b: if a.order != b.order then a.order < b.order else a.name < b.name) (
        lib.mapAttrsToList (fieldName: f: { name = fieldName; } // f) fields
      )
    );

  # Identity only — no values. Safe in the nix store by construction: there
  # is nothing in the option set that could hold a secret.
  specFile = pkgs.writeText "operator-secrets-spec.json" (
    builtins.toJSON {
      version = 1;
      secrets = lib.mapAttrsToList (
        name: s:
        {
          inherit name;
          inherit (s)
            description
            path
            owner
            group
            mode
            ;
          fields = orderedFields s.fields;
        }
        # Omitted, not null: the daemon distinguishes "no validator" (absent)
        # from an accidentally empty argv (rejected).
        // lib.optionalAttrs (s.validateCommand != null) { validate_command = s.validateCommand; }
      ) cfg.secrets;
    }
  );

  operatorSecrets = pkgs.callPackage ../packages/operator-secrets { };

  allRequiredBy = lib.unique (lib.concatMap (s: s.requiredBy) (lib.attrValues cfg.secrets));

  # Every distinct directory a secret is written into. The daemon creates
  # them too, but declaring them keeps ownership/mode under systemd's
  # control. Identical to services/secrets.nix's rule for /var/credentials,
  # so importing both merges instead of conflicting.
  secretDirs = lib.unique (map (s: builtins.dirOf s.path) (lib.attrValues cfg.secrets));
in
{
  options = namespaced __curPos {
    secrets = lib.mkOption {
      type = lib.types.attrsOf secretType;
      default = { };
      description = "Secrets a human must carry in, collected once at boot";
    };

    socket = lib.mkOption {
      type = lib.types.str;
      default = "/run/operator-secrets/sock";
      description = ''
        Control socket the TUI clients connect to. The daemon locks its
        directory to 0700 and the socket to 0600 before binding: anyone who
        can connect can choose which credential the host trusts.
      '';
    };

    editSocket = lib.mkOption {
      type = lib.types.str;
      default = "/run/operator-secrets-edit/sock";
      description = ''
        Control socket of an edit session — the on-demand run that lets an
        operator re-enter a secret the host already stores. Deliberately
        not `socket`: a boot that is still parked owns that one, and an
        edit must not be able to take it, or its breadcrumb file, away.

        Must match `operator_secrets::EDIT_SOCKET_PATH`, which is what
        `operator-secrets-tui --edit` connects to.
      '';
    };

    validatorTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = "Seconds a single validator run may take before it counts as `error`";
    };

    retryInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = ''
        Seconds between re-runs of a validator that could not decide. The
        boot stays parked meanwhile and nothing is written or discarded, so
        a late SSO heals itself without a power cycle.
      '';
    };

    service = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "operator-secrets.service";
      description = "Systemd unit collecting the operator-provided secrets";
    };

    specFile = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = specFile;
      defaultText = lib.literalMD "generated spec JSON";
      description = "Generated spec handed to the daemon. Identity only, no values.";
    };
  };

  config = lib.mkIf (cfg.secrets != { }) {
    systemd.tmpfiles.settings."credentials-dirs" = lib.genAttrs secretDirs (_: {
      d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
    });

    # The TUI is how an operator answers over SSH; it must be on PATH.
    environment.systemPackages = [ operatorSecrets ];

    systemd.services.operator-secrets = {
      description = "Collect and validate operator-provided secrets";

      wantedBy = [ "multi-user.target" ];
      # Ordering against a target delays only the TARGET, not its member
      # services — systemd starts those in parallel, so Before=getty.target
      # does NOT hold back getty@tty1 (proven the hard way). The upstream
      # hook for "run before any login prompt" is the passive
      # getty-pre.target: every getty template ships After=getty-pre.target,
      # and units wanting to precede logins pull it in with Wants= and order
      # with Before=. Ordering only, deliberately no Requires=: a getty has
      # no data dependency on the collector, and a Requires would propagate
      # a collector restart into killing console login sessions.
      # (In the initrd var-disk-manager never faces this: no gettys there.)
      before = [
        "multi-user.target"
        "getty-pre.target"
      ]
      ++ allRequiredBy;
      # Consumers get Requires=+After= on this unit through [Install].
      requiredBy = allRequiredBy;

      # The operator must be able to SSH in to answer, and the validator
      # needs the network to reach whatever proves the credential. The
      # daemon also resolves every secret's owner/group up front (and fails
      # hard on unknown ones), so the user database must be complete first —
      # nss-user-lookup.target is the systemd-blessed sync point for that.
      after = [
        "network-online.target"
        "sshd.service"
        "nss-user-lookup.target"
      ];
      wants = [
        "network-online.target"
        "nss-user-lookup.target"
        # Passive target; inert unless a unit pulls it in. See `before`.
        "getty-pre.target"
      ];

      # The destination lives on /var; do not run before it is mounted.
      unitConfig.RequiresMountsFor = secretDirs;
      # A Before=multi-user.target oneshot holds the boot only WHILE it
      # runs; if the collector CRASHES, systemd marks it failed and boots
      # straight into a half-up multi-user (consumers missing their
      # credentials). That must never be silent — drop to emergency instead,
      # same policy as var-disk-manager in the initrd.
      unitConfig.OnFailure = "emergency.target";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # A secret that cannot be collected must park the boot, not be
        # abandoned after the default five minutes.
        TimeoutStartSec = "infinity";
        ExecStart = lib.escapeShellArgs [
          (lib.getExe operatorSecrets)
          "--spec"
          "${specFile}"
          "--socket"
          cfg.socket
          "--validator-timeout-secs"
          (toString cfg.validatorTimeout)
          "--retry-interval-secs"
          (toString cfg.retryInterval)
        ];
        StandardOutput = "journal";
        StandardError = "journal";
        # Boot-completion marker for the console UI's condition below. /run
        # is tmpfs, so this exists exactly from first successful collection
        # until the next boot — never deleted at switch time.
        ExecStartPost = "${pkgs.coreutils}/bin/touch /run/operator-secrets-boot-complete";
      };
    };

    # Fullscreen TUI on the physical console, rendering the same daemon
    # state as any SSH session; either may answer. Deliberately NOT ordered
    # After= the daemon — the daemon only "finishes" when it releases the
    # boot, which is precisely when the prompt is no longer needed. The TUI
    # retries the connect for 30s, so starting in parallel is safe.
    systemd.services.operator-secrets-console = {
      description = "operator-secrets console UI";
      wantedBy = [ "multi-user.target" ];
      before = [ "multi-user.target" ];
      after = [ "sshd.service" ];
      # BOOT-time aid only. Being wanted by multi-user.target means every
      # nixos-rebuild switch would start it again — post-boot, when a getty
      # owns /dev/console, where the TTY takeover gets the unit killed with
      # SIGHUP and would disrupt whoever is logged in. During boot the
      # marker does not exist yet (gettys are gated behind the daemon via
      # getty-pre.target); after the first successful collection it does,
      # and activation-time starts become skipped conditions, not failures.
      # Post-boot collection (e.g. a switch that adds a new secret) is done
      # over SSH with operator-secrets-tui.
      unitConfig.ConditionPathExists = "!/run/operator-secrets-boot-complete";
      # sulogin and this TUI cannot share the tty, and the emergency path is
      # where a plain shell matters most.
      conflicts = [
        "shutdown.target"
        "emergency.target"
        "rescue.target"
      ];
      serviceConfig = {
        # Boot continues in parallel by design and PID 1 prints unit status
        # straight onto /dev/console over the TUI. Same remedy plymouth
        # uses: SIGRTMIN+21 silences console status, SIGRTMIN+20 restores
        # it. ExecStopPost runs on every exit path.
        ExecStartPre = "${pkgs.util-linux}/bin/kill -s RTMIN+21 1";
        ExecStopPost = "${pkgs.util-linux}/bin/kill -s RTMIN+20 1";
        # --console: release the tty when the daemon goes away instead of
        # waiting for a keypress, and disable the quit keys — closing the
        # only visible prompt on a headless box would leave nothing to
        # return to.
        ExecStart = lib.escapeShellArgs [
          (lib.getExe' operatorSecrets "operator-secrets-tui")
          "--socket"
          cfg.socket
          "--console"
        ];
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

    # Re-entering a secret on a running host. The daemon above only ever
    # asks for what is missing, so a stored secret is otherwise unreachable
    # once the boot it collected on is over: the socket is gone with it.
    #
    # Started by `operator-secrets-tui --edit`, which then attaches — the
    # unit exists so the session's log lines land in the journal, where a
    # credential change stays on the record, instead of being interleaved
    # into the screen the operator is typing on. It is not wanted by
    # anything: nothing starts it but an operator asking.
    systemd.services.operator-secrets-edit = {
      # Named to match operator_secrets::EDIT_UNIT, which is what the TUI
      # starts. Neither side can derive the other's name.
      description = "Re-enter an operator-provided secret";
      # A boot that is still parked owns the collector and is the right
      # screen to be on; this waits rather than competing with it.
      after = [ cfg.service ];
      serviceConfig = {
        Type = "simple";
        # An operator who walks away must not leave a session holding the
        # socket. Nothing is written until an answer is accepted, so an
        # abandoned edit expires having changed nothing.
        RuntimeMaxSec = "15min";
        ExecStart = lib.escapeShellArgs [
          (lib.getExe operatorSecrets)
          "--spec"
          "${specFile}"
          "--socket"
          cfg.editSocket
          "--validator-timeout-secs"
          (toString cfg.validatorTimeout)
          "--retry-interval-secs"
          (toString cfg.retryInterval)
          "--edit"
        ];
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}

{
  lib,
  pkgs,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;

  secretType = lib.types.submodule (
    { name, config, ... }:
    {
      options = {
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

        persistent = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "If true, stored in /var/credentials (survives reboot). If false, /run/credentials (ephemeral).";
        };

        length = lib.mkOption {
          type = lib.types.int;
          default = 32;
          description = "Length of generated secret";
        };

        binary = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Generate binary secret instead of ASCII-friendly password";
        };

        symbols = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Include at least one special character in the generated password";
        };

        prefix = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Prefix to prepend to the secret (stored in .variant file)";
        };

        suffix = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Suffix to append to the secret (stored in .variant file)";
        };

        preScript = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Script to run before generating the secret";
        };

        postScript = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Script to run after generating the secret";
        };

        runAs = lib.mkOption {
          type = lib.types.str;
          default = "root";
          description = "User to run the generation script as";
        };

        runAsGroup = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Group to run the generation script as. Defaults to runAs user's primary group.";
        };

        requiredBy = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Systemd units that require this secret";
        };

        requires = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Systemd units this secret generation requires";
        };

        path = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default =
            let
              dir = if config.persistent then "var" else "run";
            in
            "/${dir}/credentials/${name}";
          description = "Path to the generated secret file";
        };

        variantPath = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default =
            let
              dir = if config.persistent then "var" else "run";
            in
            "/${dir}/credentials/${name}.variant";
          description = "Path to the variant file (with prefix/suffix applied)";
        };

        service = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "generate-secret-${name}.service";
          description = "Systemd service that generates this secret";
        };
      };
    }
  );

  mkSecretService =
    name: secret:
    let
      dir = if secret.persistent then "var" else "run";
      path = "/${dir}/credentials/${name}";
      variantPath = "${path}.variant";
      fileGroup = if secret.group != null then secret.group else secret.owner;
      runGroup = if secret.runAsGroup != null then secret.runAsGroup else secret.runAs;

      prefixFile = pkgs.writeText "secret-${name}-prefix" secret.prefix;
      suffixFile = pkgs.writeText "secret-${name}-suffix" secret.suffix;

      pwgenFlags = "-snc" + lib.optionalString secret.symbols "y";
      generateCmd =
        if secret.binary then
          "${lib.getExe pkgs.openssl} rand ${toString secret.length}"
        else
          "${lib.getExe pkgs.pwgen} ${pwgenFlags} ${toString secret.length} 1 | tr -d '\\n'";
    in
    {
      name = "generate-secret-${name}";
      value = {
        description = "Generate secret: ${name}";
        requiredBy = secret.requiredBy;
        requires = secret.requires;
        after = secret.requires;
        before = secret.requiredBy;

        unitConfig.ConditionPathExists = "!${path}";

        serviceConfig = {
          Type = "oneshot";
          User = secret.runAs;
          Group = runGroup;
          Restart = "on-failure";
          ExecStart = pkgs.writeShellScript "generate-secret-${name}" ''
            set -euo pipefail

            ${secret.preScript}

            install -Dm600 /dev/null "${path}"
            install -Dm600 /dev/null "${variantPath}"

            ${generateCmd} > "${path}"

            ${lib.optionalString (!secret.binary) ''
              # Remove trailing newline if present
              if [ "$(tail -c 1 '${path}' | wc -l)" = 1 ]; then
                truncate --size=-1 '${path}'
              fi
            ''}

            # Create variant with prefix/suffix
            cat ${prefixFile} "${path}" ${suffixFile} > "${variantPath}"

            chown ${secret.owner}:${fileGroup} "${path}" "${variantPath}"
            chmod ${secret.mode} "${path}" "${variantPath}"

            ${secret.postScript}
          '';
        };
      };
    };
in
{
  options = namespaced __curPos (
    lib.mkOption {
      type = lib.types.attrsOf secretType;
      default = { };
      description = "Secrets to generate at runtime";
    }
  );

  config = {
    systemd.tmpfiles.settings."credentials-dirs" = {
      "/var/credentials".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/run/credentials".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
    };

    systemd.services = lib.mapAttrs' mkSecretService cfg;

    _module.args.generatedSecrets = cfg;
  };
}

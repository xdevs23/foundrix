{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  format = pkgs.formats.ini { listsAsDuplicateKeys = true; };

  makeDefinitionsDirectory =
    name: partitions:
    utils.systemdUtils.lib.definitions "${name}-repart.d" format (
      lib.mapAttrs (_: v: { Partition = v; }) partitions
    );

  makePartitionAssertions =
    name: partitions:
    lib.mapAttrsToList (
      fileName: definition:
      let
        inherit (utils.systemdUtils.lib) GPTMaxLabelLength;
        label = definition.Label or "";
        labelLength = builtins.stringLength label;
      in
      {
        assertion = labelLength <= GPTMaxLabelLength;
        message = ''
          The partition label "${definition.Label}" defined for "${fileName}" is ${toString labelLength} characters long,
          but the maximum label length supported by systemd is ${toString GPTMaxLabelLength}.
        '';
      }
    ) partitions;

  # Collect filesystem format types from partition definitions to determine
  # which filesystem tools to include in the service PATH
  partitionFsTools = partitions:
    let
      formats = lib.unique (
        lib.filter (f: f != null) (
          lib.mapAttrsToList (_: p: p.Format or null) partitions
        )
      );
      toolsForFormat = fmt: {
        btrfs = [ pkgs.btrfs-progs ];
      }.${fmt} or [];
    in
    lib.concatMap toolsForFormat formats;
in
{
  options = {
    systemd.repartConfig = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            device = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Target disk device path. When set, a systemd-repart@<name> service
                is automatically created to partition this device at boot.
              '';
            };
            partitions = lib.mkOption {
              type =
                with lib.types;
                attrsOf (
                  attrsOf (oneOf [
                    str
                    int
                    bool
                    (listOf str)
                  ])
                );
              default = { };
              example = {
                "50-backups" = {
                  Type = "linux-generic";
                  UUID = "00000000-0000-4000-9000-000000000160";
                  Format = "btrfs";
                  Label = "backups";
                  Minimize = "off";
                  Encrypt = "off";
                  SizeMinBytes = "64G";
                  SplitName = "-";
                  GrowFileSystem = "on";
                };
              };
              description = ''
                Specify partitions according to the regular systemd.repart configuration. See {manpage}`repart.d(t)`.
              '';
            };
          };
        }
      );
      default = { };
      description = ''
        systemd-repart configuration sets. Each attribute name becomes the repart configuration name.
        When `device` is set, the corresponding systemd service is auto-generated.
      '';
    };
    systemd.repartConfigDirs = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      description = ''
        Mapping from repart configuration name to the generated directory
        containing the corresponding `*.conf` files.
        Derived from `systemd.repartConfig` during evaluation.
      '';
    };
  };

  config =
    let
      configsWithDevice = lib.filterAttrs (_: cfg: cfg.device != null) config.systemd.repartConfig;
    in
    {
      assertions = lib.concatLists (
        lib.mapAttrsToList (
          name: cfg: makePartitionAssertions name cfg.partitions
        ) config.systemd.repartConfig
      );

      system.build.repartConfigs = lib.mapAttrs' (name: cfg: {
        name = name;
        value = makeDefinitionsDirectory name cfg.partitions;
      }) config.systemd.repartConfig;

      environment.etc = lib.mapAttrs' (name: cfg: {
        name = "${name}-repart.d";
        value.source = config.system.build.repartConfigs.${name};
      }) config.systemd.repartConfig;

      systemd.repartConfigDirs = lib.mapAttrs' (
        name: _: lib.nameValuePair name config.system.build.repartConfigs.${name}
      ) config.system.build.repartConfigs;

      # Auto-generate systemd-repart@<name> services for configs with a device
      systemd.services = lib.mapAttrs' (name: cfg:
        let
          deviceUnit = "${utils.escapeSystemdPath cfg.device}.device";
        in
        lib.nameValuePair "systemd-repart@${name}" {
          description = "Repart ${name}";
          requires = [ deviceUnit ];
          after = [ deviceUnit ];
          wantedBy = [ "local-fs.target" ];
          path = partitionFsTools cfg.partitions;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.systemd}/bin/systemd-repart --definitions=${config.systemd.repartConfigDirs.${name}} --dry-run=no --empty=allow ${cfg.device}";
          };
        }
      ) configsWithDevice;
    };
}

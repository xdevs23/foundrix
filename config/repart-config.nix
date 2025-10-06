{
  config, lib, pkgs, utils, ...
}:

let
  format = pkgs.formats.ini { listsAsDuplicateKeys = true; };

  makeDefinitionsDirectory = name: partitions:
    utils.systemdUtils.lib.definitions "${name}-repart.d" format (
      lib.mapAttrs (_: v: { Partition = v; }) partitions
    );

  makePartitionAssertions = name: partitions: lib.mapAttrsToList (
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
in
{
  options = {
    systemd.repartConfig = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          partitions = lib.mkOption {
            type =
              with lib.types;
              attrsOf (attrsOf (oneOf [ str int bool (listOf str)]));
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
      });
      default = { };
      description = ''
        systemd-repart configuration sets. Each attribute name becomes the repart configuration name.
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

  config = {
    assertions = lib.concatLists (lib.mapAttrsToList
      (name: cfg: makePartitionAssertions name cfg.partitions)
      config.systemd.repartConfig);

    system.build.repartConfigs = lib.mapAttrs' (name: cfg: {
      name = name;
      value = makeDefinitionsDirectory name cfg.partitions;
    }) config.systemd.repartConfig;

    environment.etc = lib.mapAttrs' (name: cfg: {
      name = "${name}-repart.d";
      value.source = config.system.build.repartConfigs.${name};
    }) config.systemd.repartConfig;

    systemd.repartConfigDirs =
      lib.mapAttrs'
        (name: _: lib.nameValuePair name config.system.build.repartConfigs.${name})
        config.system.build.repartConfigs;
  };
}
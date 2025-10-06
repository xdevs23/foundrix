{
  config, lib, pkgs, utils, ...
}:

let
  cfg = config.systemd.repartConfig;

  format = pkgs.formats.ini { listsAsDuplicateKeys = true; };

  makeDefinitionsDirectory = name: partitions:
    utils.systemUtils.lib.definitions "${name}-repart.d" format (
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
              "10-root" = rec {
                Type = "root";
                Label = "main";
                Format = "btrfs";
                Subvolumes = "/@store /@nix-var /@var /@home";
                MakeDirectories =  Subvolumes;
                Minimize = "off";
                Encrypt = "tpm2";
                SplitName = "-";
                FactoryReset = "yes";
              };
            };
            description = ''
              Specify partitions according to the regular systemd.repart configuration. See {manpage}`repart.d(t)`.
            '';
          };
          confDir = lib.mkOption {
            type = lib.types.str;
            description = "Where the configuration will be located at runtime";
          };
        };
      });
      default = { };
      description = ''
        systemd-repart configuration sets. Each attribute name becomes the repart configuration name.
      '';
    };
  };

  config = lib.mkMerge (lib.mapAttrsToList (name: repartCfg:
    let
      definitionsDirectory = makeDefinitionsDirectory name repartCfg.partitions;
      partitionAssertions = makePartitionAssertions name repartCfg.partitions;
      repartDir = "${name}-repart.d";
    in
    {
      assertions = partitionAssertions;

      systemd.repartConfig.${name}.confDir = "${definitionsDirectory}";

      environment.etc.${repartDir}.source = definitionsDirectory;

      system.build.repartConfigs.${name} = definitionsDirectory;
    }
  ) cfg);
}

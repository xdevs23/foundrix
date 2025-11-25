{
  namespaced,
  namespacedCfg,
  lib,
  config,
  modulesPath,
  ...
}:
{
  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  options = namespaced __curPos {
    name = lib.mkOption {
      type = lib.types.str;
      default = config.boot.uki.name;
      description = "Name of the disk image, UKI name by default";
    };
    bootloader.extraConfig = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Additional configuration to add to the bootloader configuraion (only for supported bootloaders)";
    };
    partitionIds = lib.mkOption {
      type = with lib.types; attrsOf str;
      readOnly = true;
      default = {
        esp = "10-esp";
        root = "15-root";
        nixos = "16-nixos";
        nix = "18-nix";
        storeVerity = "20-store-verity";
        emptyStoreVerity = "25-store-verity";
        store = "30-store";
        emptyStore = "35-empty-store";
      };
      description = "Partition IDs used for image.repart";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      image.repart = {
        inherit (cfg) name;
        split = true;
      };
    };
}

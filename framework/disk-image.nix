{
  namespaced,
  namespacedCfg,
  lib,
  config,
  pkgs,
  modulesPath,
  foundrixModules,
  ...
}:
{
  imports = [
    "${modulesPath}/image/repart.nix"
    foundrixModules.config.filesystem.nix-store
  ];

  options = namespaced __curPos {
    name = lib.mkOption {
      type = lib.types.str;
      default = config.boot.uki.name;
      description = "Name of the disk image, UKI name by default";
    };
    efi.enable = (lib.mkEnableOption "EFI suppport") // {
      default = pkgs.hostPlatform.is64bit;
    };
    readOnlyNixStore = lib.mkEnableOption "read-only nix store";
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
      partitionIds = cfg.partitionIds;
    in
    {
      image.repart =
        let
          inherit (pkgs.hostPlatform) efiArch;
        in
        {
          inherit (cfg) name;
          split = true;

          partitions = {
            ${partitionIds.esp} = lib.mkIf cfg.efi.enable {
              contents = {
                "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
                  "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

                "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
                  "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";

                "/loader/loader.conf".source = pkgs.writeText "loader.conf" ''
                  timeout ${toString config.boot.loader.timeout}
                  ${lib.concatMapStrings (x: "${x}\n") cfg.bootloader.extraConfig}
                '';
              };
              repartConfig = {
                Type = "esp";
                Label = "esp";
                UUID = lib.toLower "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
                Format = "vfat";
                SizeMinBytes = "512M";
                SplitName = "-";
              };
            };
            ${partitionIds.store} = {
              storePaths = [ config.system.build.toplevel ];
              stripNixStorePrefix = true;
              repartConfig = rec {
                Type = "root";
                SplitName = "store";
                Label =
                  let
                    version = config.system.image.version or null;
                  in
                  "${SplitName}${if version != null then "_${version}" else ""}";
                UUID = lib.toLower "00000000-0000-4000-9000-000000000200";
                Format = if cfg.readOnlyNixStore then "erofs" else "btrfs";
                Compression = "lz4";
                ReadOnly = if cfg.readOnlyNixStore then "yes" else "no";
                SizeMinBytes = "16G";
              };
            };
          };
        };

      foundrix.config.filesystem.nix-store =
        let
          repartCfg = config.image.repart.partitions.${partitionIds.store}.repartConfig;
        in
        {
          device = "PARTLABEL=${repartCfg.Label}";
          fsType = repartCfg.Format;
        };
    };
}

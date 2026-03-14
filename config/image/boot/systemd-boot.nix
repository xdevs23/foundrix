{
  config,
  pkgs,
  lib,
  namespaced,
  namespacedCfg,
  traitTypes,
  ...
}:
let
  efiArch = pkgs.stdenv.hostPlatform.efiArch;
  partitionIds = config.foundrix.config.image.partition-ids;
  updateMethod = config.foundrix.traits.image.updateMethod;
  hasVersionedUpdates = updateMethod == traitTypes.image.updateMethod.systemd-sysupdate;
  readOnlyStore = config.foundrix.traits.filesystem.readOnlyStore;
in
{
  imports = [
    ../partition-ids.nix
  ];

  options = namespaced __curPos {
    timeout = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Boot menu timeout in seconds";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      boot.loader.systemd-boot.enable = true;
      boot.loader.systemd-boot.graceful = true;
      boot.loader.efi.canTouchEfiVariables = false;
      boot.loader.timeout = cfg.timeout;

      image.repart.partitions.${partitionIds.esp} = {
        contents = {
          # systemd-boot EFI binary
          "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
            "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

          # Unified Kernel Image
          "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
            "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";

          # Boot loader configuration
          "/loader/loader.conf".source = pkgs.writeText "loader.conf" ''
            timeout ${toString cfg.timeout}
          '';
        };

        repartConfig = {
          Type = "esp";
          UUID = lib.toLower "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
          Format = "vfat";
          SizeMinBytes = "512M";
          SplitName = "esp";
        };
      };

      # On writable-store systems, nixos-rebuild installs a default nixos.efi
      # that duplicates the foundrix UKI. Remove it after bootloader install,
      # but only if nixos-rebuild has created its own kernel+initrd entries.
      boot.loader.systemd-boot.extraInstallCommands = lib.mkIf (!readOnlyStore) ''
        if [ -d /boot/EFI/nixos ] && [ "$(ls -A /boot/EFI/nixos/ 2>/dev/null)" ]; then
          ${lib.getExe' pkgs.coreutils-full "rm"} -f /boot/EFI/Linux/nixos.efi
          ${lib.getExe' pkgs.coreutils-full "rmdir"} /boot/EFI/Linux 2>/dev/null || true
        fi
      '';

      # Configure OTA artifact for UKI when A/B updates enabled
      foundrix.framework = lib.optionalAttrs hasVersionedUpdates {
        ota-build.artifacts."${config.boot.uki.name}_${config.system.image.version}.efi" = {
          source = "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
        };
      };
    };
}

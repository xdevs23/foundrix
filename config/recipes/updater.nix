# USB updater recipe - creates a bootable live image that applies A/B updates via systemd-sysupdate.
#
# This module expects `targetConfig` to be passed as a module arg containing the
# target system's evaluated NixOS configuration.
#
# Usage in lib/images.nix:
#   mkUpdaterSystem = { targetConfig, ... }: lib.nixosSystem {
#     specialArgs = { inherit targetConfig; };
#     modules = [ foundrixModules.config.recipes.updater ];
#   };
{
  config,
  pkgs,
  targetConfig,
  foundrixModules,
  ...
}:
let
  partitionIds = targetConfig.foundrix.config.image.partition-ids;
  targetVersion = targetConfig.system.image.version;
  targetUkiName = targetConfig.boot.uki.name;

  # The OTA update directory from the target config
  otaDir = targetConfig.system.build.otaUpdate;

  # ESP partition label from target (if configured)
  espLabel = targetConfig.image.repart.partitions.${partitionIds.esp}.repartConfig.Label or "esp";

  updateScript = pkgs.writeShellScriptBin "update-system" ''
    set -euo pipefail
    clear

    echo "Mounting target ESP..."
    mkdir -p /boot-target
    mount -o umask=0077,fmask=0077,dmask=0077,noatime \
      PARTLABEL=${espLabel} /boot-target || {
      echo "Failed to mount ESP. Is the system installed?"
      echo "Press ENTER to reboot."
      read -r
      systemctl reboot
    }

    echo "Checking available updates..."
    ${config.systemd.package}/lib/systemd/systemd-sysupdate list || true

    echo ""
    echo "Updating to ${targetConfig.system.nixos.distroName} ${targetVersion}..."
    ${config.systemd.package}/lib/systemd/systemd-sysupdate update || {
      echo ""
      echo "Update failed, check log above for details."
      echo "Press ENTER to reboot."
      read -r
      systemctl reboot
    }

    echo ""
    echo "Update complete."
    echo "Press ENTER to reboot."
    read -r
    systemctl reboot
  '';
in
{
  imports = [
    foundrixModules.profiles.minimal-image
    foundrixModules.config.image.store.erofs-readonly
    foundrixModules.config.image.boot.systemd-boot
    foundrixModules.config.greetd-autostart
    foundrixModules.config.live
  ];

  # Configure greetd to auto-start the update script
  foundrix.config.greetd-autostart = {
    package = updateScript;
    user = "root";
  };

  # No boot menu needed for single-purpose live image
  foundrix.config.image.boot.systemd-boot.timeout = 0;

  # Disable the automatic sysupdate timer - we run the update manually
  systemd.timers.systemd-sysupdate.enable = false;

  # Configure systemd-sysupdate with local file transfers
  systemd.sysupdate = {
    enable = true;

    transfers = {
      "10-uki" = {
        Source = {
          Type = "regular-file";
          Path = "${otaDir}";
          MatchPattern = [ "${targetUkiName}_@v.efi" ];
        };
        Target = {
          Type = "regular-file";
          Path = "/boot-target/EFI/Linux";
          MatchPattern = "${targetUkiName}_@v.efi";
          Mode = "0444";
          InstancesMax = 2;
        };
      };

      "20-store" = {
        Source = {
          Type = "regular-file";
          Path = "${otaDir}";
          MatchPattern = [ "store_@v.img" ];
        };
        Target = {
          Type = "partition";
          Path = "auto";
          MatchPattern = "store_@v";
          InstancesMax = 2;
        };
      };
    };
  };

  boot.uki.name = "${targetUkiName}_updater";
  system.nixos.distroId = "${targetConfig.system.nixos.distroId}-updater";
  system.nixos.distroName = "${targetConfig.system.nixos.distroName} Updater";

  system.stateVersion = targetConfig.system.stateVersion;
  system.image = targetConfig.system.image;
}

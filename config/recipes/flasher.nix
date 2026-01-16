# USB flasher recipe - creates a bootable live image that flashes the target system to disk.
#
# This module expects `targetConfig` to be passed as a module arg containing the
# target system's evaluated NixOS configuration.
#
# Usage in lib/images.nix:
#   mkFlasherSystem = { targetConfig, ... }: lib.nixosSystem {
#     specialArgs = { inherit targetConfig; };
#     modules = [ foundrixModules.config.recipes.flasher ];
#   };
{
  config,
  lib,
  pkgs,
  targetConfig,
  foundrixModules,
  ...
}:
let
  targetBuild = targetConfig.system.build;
  targetImageDrv = targetBuild.finalImage or targetBuild.image;
  targetImage = "${targetImageDrv}/${targetConfig.image.fileName}";

  flashScript = pkgs.writeShellScriptBin "flash-disk" ''
    set -euo pipefail
    clear

    echo -e "\033[1m${config.system.nixos.distroName}\033[0m"

    DISK=$(
      lsblk -b -dn -o NAME,SIZE,RM,TYPE,TRAN \
      | awk '$4=="disk" && $5!="usb" {print $2, $1}' \
      | while read -r SIZE DEV; do
        if findmnt -rn -S "/dev/$DEV" >/dev/null 2>&1 \
        || lsblk -ln -o NAME "/dev/$DEV" | tail -n +2 | xargs -I{} findmnt -rn -S "/dev/{}" >/dev/null 2>&1; then
          continue
        fi
        if command -v lsof >/dev/null 2>&1; then
          lsof -w -t "/dev/$DEV"* >/dev/null 2>&1 && continue
        fi
        printf '%s /dev/%s\n' "$SIZE" "$DEV"
      done \
      | sort -nr \
      | head -n1 \
      | cut -d' ' -f2 \
    )

    if [[ -z ''${DISK:-} ]]; then
      echo "No available disk found."
      echo "The flasher requires a non-USB disk to be connected."
      echo ""
      echo "Press ENTER to reboot."
      read -r
      systemctl reboot
    else
      echo ""
      echo "Flashing ${targetImage} → ''${DISK}"
      echo ""
      echo "Please confirm you want to flash ${targetImage} to ''${DISK}"
      echo "Press ENTER to continue"
      read -r
      ${lib.getExe pkgs.bmaptool} copy --nobmap "${targetImage}" "''${DISK}"
      sync
      echo ""
      echo "Flash complete!"
      echo "Press ENTER to reboot."
      read -r
      systemctl reboot
    fi
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

  # Configure greetd to auto-start the flash script
  foundrix.config.greetd-autostart = {
    package = flashScript;
    user = "root";
  };

  # No boot menu needed for single-purpose live image
  foundrix.config.image.boot.systemd-boot.timeout = 0;

  # Additional packages for disk operations
  environment.systemPackages = with pkgs; [
    bmaptool
    util-linux
    coreutils
    lsof
  ];

  # Naming based on target
  boot.uki.name = "${targetConfig.boot.uki.name}_flasher";
  system.nixos.distroId = "${targetConfig.system.nixos.distroId}-flasher";
  system.nixos.distroName = "${targetConfig.system.nixos.distroName} Flasher";

  # Inherit version and state from target
  system.stateVersion = targetConfig.system.stateVersion;
  system.image = targetConfig.system.image;
}

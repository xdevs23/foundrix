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

  flasher-tui = pkgs.callPackage ../../packages/flasher-tui { };

  imageIsCompressed = lib.hasSuffix ".zst" targetConfig.image.fileName;

  # If target image is already zstd-compressed, use it directly.
  # Otherwise, compress it to save store space on the flasher USB.
  flasherImage = pkgs.runCommand "flasher-image" {
    nativeBuildInputs = [ pkgs.zstd ];
  } ''
    mkdir -p $out
    ${if imageIsCompressed then ''
      ln -s "${targetImage}" "$out/image.raw.zst"
      zstdcat "${targetImage}" | wc -c > "$out/uncompressed-size"
    '' else ''
      zstd -T0 -9 "${targetImage}" -o "$out/image.raw.zst"
      stat -c %s "${targetImage}" > "$out/uncompressed-size"
    ''}
  '';

  flashScript = pkgs.writeShellScriptBin "flash-disk" ''
    exec ${lib.getExe flasher-tui} \
      --image "${flasherImage}/image.raw.zst" \
      --image-name "${targetConfig.system.nixos.distroName}" \
      --image-size "$(cat "${flasherImage}/uncompressed-size")"
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
  foundrix.config.image.boot.systemd-boot.timeout = lib.mkForce 0;
  foundrix.framework.repart-disk-image.seed = "24000000-0000-4000-9000-000000000000";

  environment.systemPackages = with pkgs; [
    util-linux
  ];

  # The flasher bundles the target image in its nix store closure, so it
  # needs a much larger store partition than a normal system
  foundrix.config.image.store.erofs-readonly.sizeMin = "12G";

  # The flasher image is meant to be dd'd to USB — don't compress it
  image.repart.compression.enable = lib.mkForce false;

  # The flasher is a live image — override the target's filesystem layout
  fileSystems = lib.mkForce {
    "/" = {
      fsType = "tmpfs";
      options = [ "size=10%" "noatime" "mode=0755" ];
    };
    "/nix/store" = {
      device = "/dev/disk/by-partlabel/store";
      fsType = "erofs";
      options = [ "noatime" ];
      neededForBoot = true;
    };
    "/boot" = {
      device = "/dev/disk/by-partuuid/${lib.toLower "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"}";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" "noatime" ];
    };
  };

  systemd.repart.enable = lib.mkForce false;
  boot.initrd.systemd.repart.enable = lib.mkForce false;

  # Wipe all device-specific repart configs and their services
  systemd.repartConfig = lib.mkForce { };

  # Naming based on target
  boot.uki.name = "${targetConfig.boot.uki.name}_flasher";
  system.nixos.distroId = "${targetConfig.system.nixos.distroId}-flasher";
  system.nixos.distroName = "${targetConfig.system.nixos.distroName} Flasher";

  # Inherit version and state from target
  system.stateVersion = targetConfig.system.stateVersion;
  system.image = targetConfig.system.image;
}

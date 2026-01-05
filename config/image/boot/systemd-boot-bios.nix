{
  config,
  pkgs,
  lib,
  namespacedCfg,
  ...
}:
let
  partitionIds = config.foundrix.config.image.partition-ids;
  bootCfg = namespacedCfg {
    file = toString ./systemd-boot.nix;
    line = 0;
    column = 0;
  };

  kernelPath = "${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}";
  initrdPath = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";

  # Shared syslinux config template generator
  mkSyslinuxConfig =
    { timeout, kernelParams }:
    ''
      TIMEOUT ${toString (timeout * 10)}
      DEFAULT nixos
      LABEL nixos
        LINUX /boot/vmlinuz
        INITRD /boot/initrd
        APPEND ${kernelParams}
    '';

  # For image build: static kernel params
  imageSyslinuxConfig = pkgs.writeText "syslinux.cfg" (mkSyslinuxConfig {
    timeout = bootCfg.timeout;
    kernelParams = "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}";
  });

  # Script to update syslinux config on system activation
  syslinuxUpdater = ''
    set -e
    system="$1"

    echo "Updating syslinux configuration for BIOS boot..."

    export PATH="$PATH:${lib.strings.makeBinPath [ pkgs.coreutils-full ]}"

    kernelParams="$(< "$system/kernel-params")"

    cat > /boot/syslinux.cfg <<EOF
    ${mkSyslinuxConfig {
      timeout = bootCfg.timeout;
      kernelParams = "init=$system/init $kernelParams";
    }}
    EOF

    echo "Copying kernel and initrd to /boot..."
    cp -f "$system/kernel" /boot/boot/vmlinuz
    cp -f "$system/initrd" /boot/boot/initrd

    echo "Syslinux configuration updated successfully"
  '';
in
{
  imports = [
    ./systemd-boot.nix
  ];

  boot.loader.systemd-boot.extraInstallCommands = syslinuxUpdater;

  # Add syslinux files to ESP
  image.repart.partitions.${partitionIds.esp}.contents = {
    # Syslinux configuration
    "/syslinux.cfg".source = imageSyslinuxConfig;

    # BIOS boot kernel and initrd
    "/boot/vmlinuz".source = kernelPath;
    "/boot/initrd".source = initrdPath;

    # Syslinux bootloader binary
    "/ldlinux.c32".source = "${pkgs.syslinux}/share/syslinux/ldlinux.c32";
  };

  # Install syslinux MBR at image build time
  system.build.finalImage = config.system.build.image.overrideAttrs (
    _: prev: {
      nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [
        pkgs.syslinux
        pkgs.gptfdisk
      ];
      postBuild = ''
        ${prev.postBuild or ""}

        echo "Installing syslinux MBR (gptmbr.bin)..."
        dd if=${pkgs.syslinux}/share/syslinux/gptmbr.bin of=${config.image.baseName}.raw bs=440 count=1 conv=notrunc

        echo "Setting legacy_boot attribute on ESP (partition 1)..."
        sgdisk --attributes=1:set:2 ${config.image.baseName}.raw

        echo "Installing syslinux to ESP..."
        syslinux --offset=$((2048 * 512)) --install ${config.image.baseName}.raw
      '';
    }
  );

  environment.systemPackages = [ pkgs.syslinux ];
}

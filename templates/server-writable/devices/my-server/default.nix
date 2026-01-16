# This is the device-specific configuration.
# Here's where you configure kernel packages and modules, architecture, file systems, peripherals, etc.
# Generally the device-specific configuration works exactly like the usual configuration, with the unique
# difference that foundrix-provided device.* options can't be set outside the device-specific configuration
# to avoid breaking the separation between device-agnostic and device-specific configuration.
# If you're familiar with AOSP, you will know this concept as "device trees" and "ROM source".
# The configuration.nix is the "ROM source" while this file here in the "devices" directory is the "device tree".
# As of right now, there is no strict separation at runtime like there is on AOSP, so to NixOS it does,
# in a techical sense, not make a difference whether you put it here or in configuration.nix.
{
  pkgs,
  lib,
  modulesPath,
  foundrixModules,
  ...
}:
{
  imports = [
    # VM/cloud guest support - remove or replace for bare metal
    "${modulesPath}/profiles/qemu-guest.nix"

    ./filesystems.nix

    # Foundrix image modules
    foundrixModules.profiles.image.server-writable # btrfs store + UEFI/BIOS boot
    foundrixModules.config.runtime.repart.var # runtime /var partition
  ];

  # Device configuration like name, platforms etc.
  device = {
    name = "my-server";
    # Platforms this device supports. Usually, this only contains one value, but can be more.
    platforms = [ "x86_64" ];
    # If your setup is any more complex than a simple TTY, you'll find that cross-compilation breaks.
    # This is why it's disabled here in the template. If you want to build for architectures other than
    # your build platform, you have to set this to true. The alternative is to use binfmt emulation
    # and just pretend to be the host platform which works a lot better for many scenarios but is also slower.
    crossCompile = false;
  };

  # REQUIRED: Device path where runtime partitions (/var) will be created.
  # Use stable paths like /dev/disk/by-id/... or /dev/disk/by-path/...
  # Examples:
  #   Hetzner volume:  "/dev/disk/by-id/scsi-0HC_Volume_12345678"
  #   NVMe:            "/dev/disk/by-id/nvme-Samsung_SSD_..."
  #   SATA:            "/dev/disk/by-id/ata-WDC_WD10EZEX_..."
  foundrix.config.image.device.dataDevice = "/dev/disk/by-id/CHANGE-ME";

  # Boot menu timeout (seconds)
  foundrix.config.image.boot.systemd-boot.timeout = 1;

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  # Networking - adjust for your setup
  networking.useDHCP = false;
  systemd.network.enable = true;
  systemd.network.networks."10-wan" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "ipv4";
    linkConfig.RequiredForOnline = "routable";
  };
}

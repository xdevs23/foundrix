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
  ...
}:
{
  imports = [
    ./filesystems.nix
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

  boot.loader.timeout = 1;
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
}

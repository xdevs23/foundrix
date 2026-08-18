{
  lib,
  pkgs,
  traitTypes,
  ...
}:
{
  foundrix.traits.system.purpose = traitTypes.system.purpose.live;

  # Allow passwordless login for live environment
  users.allowNoPasswordLogin = true;

  # Emergency/debug access
  boot.initrd.systemd = {
    emergencyAccess = true;
    users.root.shell = pkgs.runtimeShell;
  };

  # Disable network by default - live images often run offline
  systemd.network.wait-online.enable = false;
  systemd.network.enable = lib.mkOverride 60 false;
  networking.useDHCP = false;

  # A live image boots from removable media, so the initrd must see the
  # media it booted from. NixOS's default initrd modules cover SATA/NVMe/SD
  # plus USB host controllers and keyboards, but not USB mass storage -
  # nixos-generate-config would normally add those, and image-based systems
  # never run it. Without usb_storage/uas, the initrd cannot find its own
  # store partition on a USB stick and drops to emergency mode.
  boot.initrd.availableKernelModules =
    lib.optionals
      (
        pkgs.stdenv.hostPlatform.isx86_64
        || pkgs.stdenv.hostPlatform.isAarch64
        || pkgs.stdenv.hostPlatform.isRiscV64
      )
      [
        "usb_storage"
        "uas"
        # Already in the NixOS defaults, listed for self-sufficiency
        "sd_mod"
        "mmc_block"
      ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
      # Sticks in USB4/Thunderbolt ports route through the Thunderbolt driver.
      # Only x86_64 kernels ship the module.
      "thunderbolt"
    ];

  # Basic utilities expected in a live environment
  environment.systemPackages = with pkgs; [
    coreutils
    util-linux
  ];
}

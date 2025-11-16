{ lib, pkgs, ... }:
{
  boot.initrd.availableKernelModules =
    # Typically, modern desktop-like systems will have NVMe and USB
    lib.optionals
      (
        pkgs.stdenv.hostPlatform.isx86_64
        || pkgs.stdenv.hostPlatform.isAarch64
        || pkgs.stdenv.hostPlatform.isRiscV64
      )
      [
        "nvme"
        "usb_storage"
        "usbhid"
        "xhci_pci"
        "sd_mod"
        "uas"
      ];
}

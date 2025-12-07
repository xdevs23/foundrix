# This module assumes that nixos-hardware is available
{ foundrixModules, inputs, ... }:
{
  imports = with inputs.nixos-hardware.nixosModules; [
    common-pc
    common-cpu-amd
    common-cpu-amd-pstate
    common-gpu-amd
    common-pc-ssd
    framework-16-7040-amd
    foundrixModules.hardware.gpu.amd
    foundrixModules.hardware.peripherals.fingerprint
  ];
  foundrix.hardware.gpu.amd.gpuTargets = [
    "gfx1100"
    "gfx1101"
    "gfx1102"
  ];
  boot.kernelParams = [
    "ttm.pages_limit=12582912"
    "ttm.page_pool_size=12582912"
  ];

  # Support for framework keyboard backlight
  services.udev.extraRules = ''
    KERNEL=="hidraw*", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0018", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
  '';
}

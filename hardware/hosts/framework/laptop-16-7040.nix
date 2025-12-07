# This module assumes that nixos-hardware is available
{
  foundrixModules,
  inputs,
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
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

  options = namespaced __curPos {
    vram = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "Amount of VRAM to make available in GB. Sets TTM pages_limit and page_pool_size kernel parameters.";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      # TTM parameters are specified in 4 KiB pages
      # pages = GB * 1024 * 1024 / 4 = GB * 262144
      ttmPages = cfg.vram * 262144;
    in
    {
      foundrix.hardware.gpu.amd.gpuTargets = [
        "gfx1100"
        "gfx1101"
        "gfx1102"
      ];
      boot.kernelParams = [
        "ttm.pages_limit=${toString ttmPages}"
        "ttm.page_pool_size=${toString ttmPages}"
      ];

      # Support for framework keyboard backlight
      services.udev.extraRules = ''
        KERNEL=="hidraw*", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0018", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
      '';
    };
}

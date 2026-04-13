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
    setAmdGpuTargets = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set only the AMD GPU targets you need. If disabled, all default targets are included.";
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
      foundrix.hardware.gpu.amd.gpuTargets = lib.mkIf cfg.setAmdGpuTargets [
        "gfx1100"
        "gfx1101"
        "gfx1102"
      ];
      boot.kernelParams = [
        "ttm.pages_limit=${toString ttmPages}"
        "ttm.page_pool_size=${toString ttmPages}"
        # Use 0x410 instead of 0x10 to also disable Panel Replay (fixes green artifacts)
        "amdgpu.dcdebugmask=0x410"
      ];
      hardware.fw-fanctrl = {
        enable = true;
        config = {
          defaultStrategy = "custom";
          strategies.custom = {
            fanSpeedUpdateFrequency = 1;
            movingAverageInterval = 3;
            speedCurve = [
              {
                temp = 0;
                speed = 0;
              }
              {
                temp = 49;
                speed = 0;
              }
              {
                temp = 50;
                speed = 5;
              }
              {
                temp = 55;
                speed = 7;
              }
              {
                temp = 60;
                speed = 10;
              }
              {
                temp = 65;
                speed = 20;
              }
              {
                temp = 70;
                speed = 25;
              }
              {
                temp = 75;
                speed = 30;
              }
              {
                temp = 80;
                speed = 40;
              }
              {
                temp = 81;
                speed = 45;
              }
              {
                temp = 82;
                speed = 50;
              }
              {
                temp = 83;
                speed = 55;
              }
              {
                temp = 84;
                speed = 60;
              }
              {
                temp = 85;
                speed = 70;
              }
              {
                temp = 90;
                speed = 75;
              }
              {
                temp = 92;
                speed = 78;
              }
              {
                temp = 96;
                speed = 90;
              }
              {
                temp = 100;
                speed = 100;
              }
            ];
          };
        };
      };

      # Support for framework keyboard backlight
      services.udev.extraRules = ''
        KERNEL=="hidraw*", ATTRS{idVendor}=="32ac", ATTRS{idProduct}=="0018", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
      '';

      hardware.inputmodule.enable = true;
    };
}

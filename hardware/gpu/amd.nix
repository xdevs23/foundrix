{
  config,
  lib,
  pkgs,
  pkgsUnstable,
  ...
}:
{

  options = {
    foundrix.hardware.gpu.amd = {
      overclocking.unlock = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to unlock the graphics card to support OC/UC/OV/UV features";
      };
      useUnstablePackages = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to use the latest packages of Mesa and ROCm from nixpkgs-unstable";
      };
      isSupported = lib.mkOption {
        type = lib.types.bool;
        default = true;
        readOnly = true;
        description = "Whether AMD GPU hardware is supported";
      };
      rocmPackages = lib.mkOption {
        type = with lib.types; listOf package;
        default = if config.foundrix.hardware.gpu.amd.useUnstablePackages then
          pkgsUnstable.rocmPackages
        else
          pkgs.rocmPackages;
      };
    };
  };

  config =
    let
      cfg = config.foundrix.hardware.gpu.amd;
      amdgpuClocks = pkgs.stdenv.mkDerivation rec {
        name = "amdgpu-clocks";
        src = pkgs.fetchFromGitHub {
          owner = "sibradzic";
          repo = name;
          # chore: update amdgpu-clocks revision
          rev = "60419dcda0987be3ae7afa37a5345c2399af420d";
          hash = "sha256-Z97jwjRw7/jMembBaZJaAoE2S+xxK3FQ7hAT5dn12rU=";
        };
        installPhase = ''
          mkdir -p $out/bin
          install -Dm755 ${name} $out/bin/${name}
        '';
      };
    in
    {
      boot.kernelParams =
        lib.optional cfg.graphics.amd.overclocking.unlock "amdgpu.ppfeaturemask=0xfff7ffff";

      environment.systemPackages = with (
        if config.customization.hardware.graphics.useUnstablePackages
        then pkgs.unstable else pkgs
      ); [
        opencl-headers
        clinfo
        amdgpu_top
        vulkan-tools
      ] ++ (if cfg.overclocking.unlock then [ amdgpuClocks ] else [ ]);

      hardware.amdgpu.amdvlk = {
        enable = false;
        support32Bit.enable = false;
      };
      hardware.amdgpu.initrd.enable = true;
      # Do not set this to true because the code after it already does the same
      hardware.amdgpu.opencl.enable = lib.mkForce false;
      hardware.enableRedistributableFirmware = lib.mkDefault true;
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with (if cfg.useUnstablePackages then pkgs.unstable else pkgs); [
          rocmPackages.clr
          rocmPackages.clr.icd
        ];
      };

      environment.variables = {
        # We're simplifying this here on purpose since RADV generally is more correct
        # If you'd like to use a different one, please create a PR that implements an option for it.
        AMD_VULKAN_ICD = "RADV";
      };
    };
}

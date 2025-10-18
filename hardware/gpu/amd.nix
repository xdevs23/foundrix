{
  lib,
  pkgs,
  pkgsUnstable,
  namespaced,
  namespacedCfg,
  ...
}:
{

  options = namespaced __curPos {
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
      type = with lib.types; lazyAttrsOf anything;
      default =
        if (namespacedCfg __curPos).useUnstablePackages then
          pkgsUnstable.rocmPackages
        else
          pkgs.rocmPackages;
    };
    rocmScript = {
      name = "Generate a shell script package that prepares your script for proper ROCm usage";
      type = lib.types.package;
      readOnly = true;
      default = name: script: pkgs.writeShellScriptBin name ''
        gfxver="$(${lib.getExe' (namespacedCfg __curPos).rocmPackages.rocminfo "rocminfo"} | \
          grep 'Name' | grep 'gfx' | head -n1 | ${lib.getExe pkgs.gawk} '{ print $2 }')"
        version_digits=''${gfxver#gfx}
        num_digits=''${#version_digits}
        if [ "$num_digits" -eq 4 ]; then
          major=''${version_digits:0:2}
          minor=''${version_digits:2:1}
          patch=''${version_digits:3:1}
        elif [ "$num_digits" -eq 3 ]; then
          major=''${version_digits:0:1}
          minor=''${version_digits:1:1}
          patch=''${version_digits:2:1}
        fi
        if [ "$version_digits" == "1103" ]; then
          # 1103 is not supported, it just does not appear in the list, let's use 1102 instead
          patch=2
        fi
        export HSA_OVERRIDE_GFX_VERSION="$major.$minor.$patch"
        ${script}
      '';
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
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
    lib.mkMerge [
      {
        nixpkgs.config.rocmSupport = cfg.isSupported;
        nixpkgs.config.rocmPackages = cfg.rocmPackages;
        boot.kernelParams = lib.optional cfg.overclocking.unlock "amdgpu.ppfeaturemask=0xfff7ffff";

        environment.systemPackages =
          with (if cfg.useUnstablePackages then pkgsUnstable else pkgs);
          [
            opencl-headers
            clinfo
            amdgpu_top
            vulkan-tools
          ]
          ++ (if cfg.overclocking.unlock then [ amdgpuClocks ] else [ ]);

        hardware.amdgpu.initrd.enable = true;
        # Do not set this to true because the code after it already does the same
        hardware.amdgpu.opencl.enable = lib.mkForce false;
        hardware.enableRedistributableFirmware = lib.mkDefault true;
        hardware.graphics = {
          enable = true;
          enable32Bit = true;
          extraPackages = with (if cfg.useUnstablePackages then pkgsUnstable else pkgs); [
            rocmPackages.clr
            rocmPackages.clr.icd
          ];
        };
      }
      (lib.mkIf (lib.versionOlder pkgs.lib.version "25.10") {
        # amdvlk is removed from 25.11 and this part is for pre-25.11
        # to enable RADV
        hardware.amdgpu.amdvlk = {
          enable = false;
          support32Bit.enable = false;
        };

        environment.variables = {
          AMD_VULKAN_ICD = "RADV";
        };
      })
    ];
}

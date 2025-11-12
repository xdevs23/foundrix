{ lib, pkgs, ... }:
{
  boot.initrd.availableKernelModules = [ "ahci" ];
  boot.kernelParams = [
    "elevator=bfq"
    "add_efi_memmap"
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  hardware.graphics.enable32Bit =
    lib.mkIf (!pkgs.stdenv.buildPlatform.isx86 || !pkgs.stdenv.buildPlatform.isLinux)
      (
        lib.mkForce (
          let
            buildSystem = pkgs.stdenv.buildPlatform.system;
          in
          lib.info ''
            Forcing hardware.graphics.enable32Bit = false due to unsupported cross-building i686 on ${buildSystem}
          '' false
        )
      );
}

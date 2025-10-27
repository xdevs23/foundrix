{ lib, pkgs, ... }:
{
  boot.initrd.availableKernelModules = [ "ahci" ];
  boot.kernelParams = [ "elevator=bfq" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
  hardware.graphics.enable32Bit =
    lib.mkIf (!pkgs.buildPlatform.isx86 || !pkgs.buildPlatform.isLinux)
      (
        lib.mkForce (
          let
            buildSystem = pkgs.buildPlatform.system;
          in
          lib.info ''
            Forcing hardware.graphics.enable32Bit = false due to unsupported cross-building i686 on ${buildSystem}
          '' false
        )
      );
}

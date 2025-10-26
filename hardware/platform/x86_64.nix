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
          lib.info ''
            Forcing hardware.graphics.enable32Bit to false because cross-building i686 \
            is not supported on ${pkgs.buildPlatform.system}
          '' false
        )
      );
}

{ lib, ... }: {
  boot.initrd.availableKernelModules = [ "ahci" ];
  boot.kernelParams = [ "elevator=bfq" ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

{ lib, ... }:
{
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  # This is not supported on aarch64
  hardware.graphics.enable32Bit = lib.mkForce false;
}

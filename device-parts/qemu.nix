{ modulesPath, foundrixModules, ... }:
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
    foundrixModules.hardware.gpu.vga
  ];

  device = {
    name = "qemu";
  };
}

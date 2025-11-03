{
  modulesPath,
  foundrixModules,
  lib,
  ...
}:
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
    foundrixModules.hardware.gpu.vga
    foundrixModules.config.filesystem.root-tmpfs
    foundrixModules.framework.toplevel-closure
  ];

  device = {
    name = "qemu";
  };

  fileSystems = {
    "/nix/store" = lib.mkForce {
      device = "store";
      fsType = "9p";
      options = [
        "trans=virtio"
        "version=9p2000.L"
        "cache=loose"
      ];
      neededForBoot = true;
    };
  };
}

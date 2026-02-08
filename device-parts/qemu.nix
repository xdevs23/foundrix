{
  modulesPath,
  foundrixModules,
  config,
  lib,
  ...
}:
{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"
    foundrixModules.hardware.gpu.vga
    foundrixModules.config.filesystem.root-tmpfs
    foundrixModules.config.image.device
    foundrixModules.framework.toplevel-closure
  ];

  config = lib.mkMerge [
    {
      device.name = "qemu";

      fileSystems."/nix/store" = lib.mkForce {
        device = "store";
        fsType = "9p";
        options = [
          "trans=virtio"
          "version=9p2000.L"
          "msize=104857600"
          "cache=loose"
          "ro"
        ];
        neededForBoot = true;
      };
    }
    (lib.mkIf (config.foundrix.general.qemu.dataDevice != null) {
      foundrix.config.image.device.dataDevice =
        lib.mkForce config.foundrix.general.qemu.dataDevice;
    })
  ];
}

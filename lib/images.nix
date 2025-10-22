{ lib, customLib, ... }:
{
  mkTargetOutputs =
    {
      name,
      deviceName,
      nixosConfiguration,
    }:
    let
      buildCfg = nixosConfiguration.config.system.build;
      maybeOutputs = {
        image = buildCfg.image or null;
        update = buildCfg.otaUpdate or null;
        "update@compressed" = buildCfg.compressedOtaUpdate or null;
        toplevel = buildCfg.toplevel or null;
        qemu-launch =
          if (buildCfg.image or null) == null then
            null
          else
            let
              qemuCfg = nixosConfiguration.extendModules {
                modules = [
                  (
                    { modulesPath, foundrixModules, ... }:
                    {
                      imports = [
                        "${modulesPath}/profiles/qemu-guest.nix"
                        foundrixModules.hardware.gpu.vga
                      ];
                    }
                  )
                ];
              };
              qemuBuildCfg = qemuCfg.config.system.build;
            in
            customLib.qemu-launch.${qemuCfg.pkgs.hostPlatform.qemuArch} {
              systemDisk = "${qemuBuildCfg.image}/${qemuCfg.config.image.fileName}";
            };
      };
      outputs = lib.filterAttrs (_: value: value != null) maybeOutputs;
    in
    lib.mapAttrs' (artifact: value: {
      name = "${name}/${artifact}:${deviceName}";
      inherit value;
    }) outputs;
}

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
            customLib.qemu-launch.${nixosConfiguration.pkgs.hostPlatform.qemuArch} {
              systemDisk = "${buildCfg.image}/${nixosConfiguration.config.image.fileName}";
            };
      };
      outputs = lib.filterAttrs (_: value: value != null) maybeOutputs;
    in
    lib.mapAttrs' (artifact: value: {
      name = "${name}/${artifact}:${deviceName}";
      inherit value;
    }) outputs;
}

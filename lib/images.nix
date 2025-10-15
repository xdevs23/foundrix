{ lib, ... }:
{
  mkTargetOutputs =
    {
      name,
      deviceName,
      nixosConfiguration,
    }:
    let
      cfg = nixosConfiguration.config.system.build;
      maybeOutputs = {
        image = cfg.image or null;
        update = cfg.otaUpdate or null;
        "update@compressed" = cfg.compressedOtaUpdate or null;
        toplevel = cfg.toplevel or null;
      };
      outputs = lib.filterAttrs (_: value: value != null) maybeOutputs;
    in
    lib.mapAttrs' (artifact: value: {
      name = "${name}/${artifact}:${deviceName}";
      inherit value;
    }) outputs;
}

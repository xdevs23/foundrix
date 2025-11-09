{
  pkgs,
  options,
  config,
  lib,
  foundrixModules,
  ...
}:
{
  imports = [
    foundrixModules.hardware.gpu.apple
  ];

  config = lib.mkMerge [
    (
      if (options.hardware ? asahi) then
        {
          hardware.asahi.extractPeripheralFirmware =
            (config.hardware.asahi.peripheralFirmwareDirectory or null) != null;
          environment.systemPackages = with pkgs; [
            asahi-btsync
            asahi-wifisync
            asahi-bless
            asahi-nvram
          ];
        }
      else
        { }
    )
    {
      hardware.graphics.enable32Bit = lib.mkForce false;
    }
  ];
}

{ ... }:
rec {
  mkDeviceFrameworkModules = targetPlatformConfiguration: [
    ./device-specific.nix
    targetPlatformConfiguration
  ];
  mkFinalConfiguration =
    {
      targetPlatformConfiguration,
      deviceConfiguration,
      nixosConfiguration,
    }:
    (nixosConfiguration.extendModules {
      modules = (mkDeviceFrameworkModules targetPlatformConfiguration) ++ [
        deviceConfiguration
      ];
    })
    // {
      deviceSpecific = true;
    };
  mkDeviceSpecificConfiguration =
    {
      platformModule,
      nixosConfiguration,
      deviceConfiguration,
      hostname ? null,
    }:
    mkFinalConfiguration {
      inherit deviceConfiguration;
      nixosConfiguration =
        if hostname == null then
          nixosConfiguration
        else
          nixosConfiguration.extendModules {
            modules = [
              {
                networking.hostName = hostname;
              }
            ];
          };
      targetPlatformConfiguration = platformModule;
    };
  mkDeviceSpecificConfigurations =
    devicesParams:
    builtins.mapAttrs (
      hostname: deviceParams:
      mkDeviceSpecificConfiguration {
        inherit (deviceParams) platformModule nixosConfiguration deviceConfiguration;
        inherit hostname;
      }
    ) devicesParams;
}

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
    }:
    mkFinalConfiguration {
      inherit nixosConfiguration deviceConfiguration;
      targetPlatformConfiguration = platformModule;
    };
}

{
  pkgs,
  lib,
  customLib,
  foundrixModules,
  foundrix,
  ...
}:
let
  platformDir = ../hardware/platform;
  platformFiles = builtins.attrNames (builtins.readDir platformDir);
  platformModules = builtins.filter (f: lib.hasSuffix ".nix" f) platformFiles;
  mkPlatformName =
    path:
    lib.concatStringsSep "." (lib.lists.dropEnd 1 (lib.strings.splitString "." (baseNameOf path)));
  platformNames = map mkPlatformName platformModules;
  inherit (customLib.deviceFramework) mkDeviceFrameworkModules mkFinalConfiguration;

  # Create a flasher system for a target configuration
  # Mirrors the flow of regular configs: nixosSystem + device framework + device config
  mkFlasherSystem =
    {
      targetConfig,
      targetPlatformConfiguration,
      deviceConfiguration,
      extraModules ? [ ],
    }:
    lib.nixosSystem {
      specialArgs = foundrixModules.foundrixSpecialArgs // {
        inherit targetConfig;
      };
      modules = [
        (foundrix + "/common")
        foundrixModules.config.recipes.flasher
        # Device framework (inlined from mkDeviceFrameworkModules + mkFinalConfiguration)
        ./device-specific.nix
        targetPlatformConfiguration
        deviceConfiguration
      ]
      ++ extraModules;
    };

  # Create an updater system for a target configuration (A/B updates)
  # Mirrors the flow of regular configs: nixosSystem + device framework + device config
  mkUpdaterSystem =
    {
      targetConfig,
      targetPlatformConfiguration,
      deviceConfiguration,
      extraModules ? [ ],
    }:
    lib.nixosSystem {
      specialArgs = foundrixModules.foundrixSpecialArgs // {
        inherit targetConfig;
      };
      modules = [
        (foundrix + "/common")
        foundrixModules.config.recipes.updater
        # Device framework (inlined from mkDeviceFrameworkModules + mkFinalConfiguration)
        ./device-specific.nix
        targetPlatformConfiguration
        deviceConfiguration
      ]
      ++ extraModules;
    };

  # Build the final flasher image
  mkFlasherImage =
    {
      targetConfig,
      targetPlatformConfiguration,
      deviceConfiguration,
    }:
    let
      flasherSystem = mkFlasherSystem {
        inherit targetConfig targetPlatformConfiguration deviceConfiguration;
      };
      flasherBuild = flasherSystem.config.system.build;
    in
    flasherBuild.image or null;

  # Build the final updater image
  mkUpdaterImage =
    {
      targetConfig,
      targetPlatformConfiguration,
      deviceConfiguration,
    }:
    let
      updaterSystem = mkUpdaterSystem {
        inherit targetConfig targetPlatformConfiguration deviceConfiguration;
      };
      updaterBuild = updaterSystem.config.system.build;
    in
    updaterBuild.image or null;
in
rec {
  # Export helper functions for manual flasher/updater creation
  inherit
    mkFlasherSystem
    mkUpdaterSystem
    mkFlasherImage
    mkUpdaterImage
    ;

  mkTargetOutputList =
    { nixosConfiguration, ... }@args:
    lib.optionals
      (
        # Let's limit who can build these since older architectures tend to break
        # And some architectures have broken packages
        pkgs.stdenv.buildPlatform.isLinux
        && (pkgs.stdenv.buildPlatform.isx86_64 || pkgs.stdenv.buildPlatform.isAarch64)
        && !(nixosConfiguration.disableTargetOutputs or false)
      )
      (
        map (
          platformFile:
          let
            arch = lib.removeSuffix ".nix" platformFile;
            isDeviceSpecific = nixosConfiguration.deviceSpecific or false;
            targetPlatformConfiguration = {
              imports = [ (platformDir + "/${platformFile}") ];
              nixpkgs.buildPlatform = pkgs.stdenv.buildPlatform.system;
            };
            finalConfiguration =
              if isDeviceSpecific then nixosConfiguration
              else mkFinalConfiguration (args // { inherit targetPlatformConfiguration; });
            buildCfg =
              if
                # Device-specific configs only build on matching platforms
                !(isDeviceSpecific && nixosConfiguration.pkgs.stdenv.hostPlatform.system != pkgs.stdenv.buildPlatform.system)
                # Again, just avoiding broken packages
                && (
                  finalConfiguration.pkgs.stdenv.hostPlatform.isx86_64
                  || finalConfiguration.pkgs.stdenv.hostPlatform.isAarch64
                )
                && (
                  finalConfiguration.config.device.crossCompile
                  || finalConfiguration.pkgs.stdenv.hostPlatform == finalConfiguration.pkgs.stdenv.buildPlatform
                )
                && (
                  finalConfiguration.config.device.platforms == null
                  || (
                    ((lib.lists.intersectLists platformNames finalConfiguration.config.device.platforms) != [ ])
                    && builtins.elem (mkPlatformName platformFile) finalConfiguration.config.device.platforms
                  )
                )
              then
                finalConfiguration.config.system.build
              else
                null;
          in
          builtins.addErrorContext "while constructing outputs for ${arch}" rec {
            inherit arch finalConfiguration;
            qemuCfg =
              if buildCfg == null then
                null
              else
                nixosConfiguration.extendModules {
                  modules = (mkDeviceFrameworkModules targetPlatformConfiguration) ++ [
                    ../device-parts/qemu.nix
                    (
                      if finalConfiguration.options ? home-manager then
                        (
                          { foundrixModules, ... }:
                          {
                            imports = [ foundrixModules.config.home-manager-prebuilt ];
                          }
                        )
                      else
                        { }
                    )
                    {
                      boot.kernelParams = [
                        "systemd.setenv=SYSTEMD_SULOGIN_FORCE=1"
                        "printk.devkmsg=on"
                        "earlycon"
                        "console=ttyS0,115200n8r"
                        "systemd.crash_action=emergency"
                      ];
                    }
                  ];
                };
            # Check if this is an image-based system and if A/B updates are enabled
            hasImage = (buildCfg.finalImage or buildCfg.image or null) != null;
            hasAbUpdates =
              (finalConfiguration.config.foundrix.traits.image.updateMethod or null) == "systemd-sysupdate";
            outputs = {
              image = buildCfg.finalImage or buildCfg.image or null;
              update = buildCfg.otaUpdate or null;
              "update@compressed" = buildCfg.compressedOtaUpdate or null;
              toplevel = buildCfg.toplevel or null;
              qemu-launch =
                if (qemuCfg.config.system.build.toplevelClosure or null) != null then
                  customLib.qemu-launch-closure {
                    closure = qemuCfg.config.system.build.toplevelClosure;
                    uki = "${qemuCfg.config.system.build.uki}/${qemuCfg.config.system.boot.loader.ukiFile}";
                  }
                else if (buildCfg.finalImage or buildCfg.image or null) != null then
                  let
                    qemuBuildCfg = qemuCfg.config.system.build;
                  in
                  customLib.qemu-launch {
                    systemDisk = "${buildCfg.finalImage or qemuBuildCfg.image}/${qemuCfg.config.image.fileName}";
                  }
                else
                  null;
              # Flasher for any image-based system
              flasher =
                if hasImage then
                  mkFlasherImage {
                    targetConfig = finalConfiguration.config;
                    inherit targetPlatformConfiguration;
                    deviceConfiguration = args.deviceConfiguration;
                  }
                else
                  null;
              # Updater only for A/B systems
              updater =
                if hasImage && hasAbUpdates then
                  mkUpdaterImage {
                    targetConfig = finalConfiguration.config;
                    inherit targetPlatformConfiguration;
                    deviceConfiguration = args.deviceConfiguration;
                  }
                else
                  null;
            };
          }
        ) platformModules
      );
  mkTargetOutputs =
    {
      name,
      deviceConfiguration,
      nixosConfiguration,
      seenDeviceNames ? { },
    }:
    let
      targetName = name;
      isDeviceSpecific = nixosConfiguration.deviceSpecific or false;
      maybeOutputs = mkTargetOutputList {
        inherit deviceConfiguration nixosConfiguration;
      };
    in
    let
      # Get device name from first output (all outputs have same device name)
      deviceName =
        if isDeviceSpecific then
          nixosConfiguration.config.device.name
        else if maybeOutputs == [ ] then
          null
        else
          (builtins.head maybeOutputs).finalConfiguration.config.device.name;
      alreadySeen = deviceName != null && seenDeviceNames ? ${deviceName};
    in
    if alreadySeen then
      {
        outputs = { };
        seen = seenDeviceNames;
      }
    else
      {
        outputs = lib.foldl' (
          acc:
          {
            arch,
            outputs,
            ...
          }:
          let
            filtered = lib.filterAttrs (_: value: value != null) outputs;
            # Device-specific configs use simplified naming (no device name suffix)
            renamed = lib.mapAttrs' (artifact: output: {
              name =
                if isDeviceSpecific then
                  "${targetName}/${artifact}:${arch}"
                else
                  "${targetName}/${artifact}:${deviceName}:${arch}";
              value = output;
            }) filtered;
          in
          acc // renamed
        ) { } maybeOutputs;
        seen = if deviceName == null then seenDeviceNames else seenDeviceNames // { ${deviceName} = true; };
      };
}

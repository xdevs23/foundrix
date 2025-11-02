{
  pkgs,
  lib,
  customLib,
  ...
}:
let
  platformDir = ../hardware/platform;
  platformFiles = builtins.attrNames (builtins.readDir platformDir);
  platformModules = builtins.filter (f: lib.hasSuffix ".nix" f) platformFiles;
  mkPlatformName =
    path:
    lib.concatStringsSep "." (lib.lists.dropEnd 1 (lib.strings.splitString "." (builtins.baseNameOf path)));
  platformNames = builtins.map mkPlatformName platformModules;

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
    nixosConfiguration.extendModules {
      modules = (mkDeviceFrameworkModules targetPlatformConfiguration) ++ [
        deviceConfiguration
      ];
    };
in
rec {
  mkTargetOutputList =
    { nixosConfiguration, ... }@args:
    lib.optionals
      (
        # Let's limit who can build these since older architectures tend to break
        # And some architectures have broken packages
        pkgs.stdenv.buildPlatform.isLinux
        && (pkgs.stdenv.buildPlatform.isx86_64 || pkgs.stdenv.buildPlatform.isAarch64)
        && (pkgs.stdenv.hostPlatform.isx86_64 || pkgs.stdenv.hostPlatform.isAarch64)
      )
      (
        map (
          platformFile:
          let
            arch = lib.removeSuffix ".nix" platformFile;
            targetPlatformConfiguration = {
              imports = [ (platformDir + "/${platformFile}") ];
              nixpkgs.buildPlatform = pkgs.system;
            };
            finalConfiguration = mkFinalConfiguration (args // { inherit targetPlatformConfiguration; });
            buildCfg =
              if
                finalConfiguration.config.device.platforms == null
                || (
                  ((lib.lists.intersectLists platformNames finalConfiguration.config.device.platforms) != [ ])
                  && builtins.elem (mkPlatformName platformFile) finalConfiguration.config.device.platforms
                )
              then
                finalConfiguration.config.system.build
              else
                null;
          in
          rec {
            inherit arch finalConfiguration;
            qemuCfg = nixosConfiguration.extendModules {
              modules = (mkDeviceFrameworkModules targetPlatformConfiguration) ++ [
                ../device-parts/qemu.nix
              ];
            };
            outputs = {
              image = buildCfg.image or null;
              update = buildCfg.otaUpdate or null;
              "update@compressed" = buildCfg.compressedOtaUpdate or null;
              toplevel = buildCfg.toplevel or null;
              qemu-launch =
                if (qemuCfg.config.system.build.toplevelClosure or null) != null then
                  customLib.qemu-launch-closure {
                    closure = qemuCfg.config.system.build.toplevelClosure;
                    uki = "${qemuCfg.config.system.build.uki}/${qemuCfg.config.system.boot.loader.ukiFile}";
                  }
                else if (buildCfg.image or null) != null then
                  let
                    qemuBuildCfg = qemuCfg.config.system.build;
                  in
                  customLib.qemu-launch {
                    systemDisk = "${qemuBuildCfg.image}/${qemuCfg.config.image.fileName}";
                  }
                else null;
            };
          }
        ) platformModules
      );
  mkTargetOutputs =
    {
      name,
      deviceConfiguration,
      nixosConfiguration,
    }:
    let
      targetName = name;
      maybeOutputs = mkTargetOutputList {
        inherit deviceConfiguration nixosConfiguration;
      };
    in
    lib.foldl' (
      acc:
      {
        arch,
        finalConfiguration,
        outputs,
        ...
      }:
      let
        filtered = lib.filterAttrs (_: value: value != null) outputs;
        renamed = lib.mapAttrs' (artifact: output: {
          name = "${targetName}/${artifact}:${finalConfiguration.config.device.name}:${arch}";
          value = output;
        }) filtered;
      in
      acc // renamed
    ) { } maybeOutputs;
}

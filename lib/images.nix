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
    lib.concatStringsSep "." (
      lib.lists.dropEnd 1 (lib.strings.splitString "." (builtins.baseNameOf path))
    );
  platformNames = builtins.map mkPlatformName platformModules;
  inherit (customLib.deviceFramework) mkDeviceFrameworkModules mkFinalConfiguration;
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
        # Device is not allowed to be specified in the commonized configuration.
        # In such a case, this configuration is likely device-specific and thus should not have
        # images generated. For generating images, the device framework should be used.
        # Note that using the device framework and having device-specific configs is not mutually exclusive.
        # You can still have your commonized configs and then manually combine them into a separate config,
        # for example in the case of nixos-rebuild.
        && !(nixosConfiguration.deviceSpecific or false)
        && !(nixosConfiguration.disableTargetOutputs or false)
      )
      (
        map (
          platformFile:
          let
            arch = lib.removeSuffix ".nix" platformFile;
            targetPlatformConfiguration = {
              imports = [ (platformDir + "/${platformFile}") ];
              nixpkgs.buildPlatform = pkgs.stdenv.buildPlatform.system;
            };
            finalConfiguration = mkFinalConfiguration (args // { inherit targetPlatformConfiguration; });
            buildCfg =
              if
                # Again, just avoiding broken packages
                (finalConfiguration.pkgs.stdenv.hostPlatform.isx86_64 || finalConfiguration.pkgs.stdenv.hostPlatform.isAarch64)
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
                      { foundrixModules, ... }:
                      {
                        imports = [ foundrixModules.config.home-manager-prebuilt ];
                        boot.kernelParams = [
                          "systemd.setenv=SYSTEMD_SULOGIN_FORCE=1"
                          "printk.devkmsg=on"
                          "earlycon"
                          "console=ttyS0,115200n8r"
                          "systemd.crash_action=emergency"
                        ];
                      }
                    )
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

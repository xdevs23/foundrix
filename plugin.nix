{
  outputs =
    { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
      foundrixPackages =
        pkgs:
        (lib.filesystem.packagesFromDirectoryRecursive {
          inherit (pkgs) callPackage;
          directory = ./packages;
        });
      defaultSpecialArgs = {
        foundrix = self;
        foundrixModules = self.nixosModules;
        inherit foundrixPackages;
      }
      // (import ./special.nix {
        inherit lib;
        foundrix = self;
      });

      customLib =
        system:
        import ./lib (
          defaultSpecialArgs
          // {
            inherit lib;
            pkgs = import nixpkgs { inherit system; };
          }
        );

      traverseDirectory = import ./lib/traverse-directory.nix { inherit lib; };

      collectDeviceConfigs =
        dir:
        if builtins.pathExists dir then
          traverseDirectory {
            directory = dir;
            includeDirectories = true;
          }
        else
          { };

    in
    {
      packages = forAllSystems (
        system:
        let
          devices = collectDeviceConfigs (self + "/devices");
          customLibInstance = customLib system;

          mergedPackages = lib.mergeAttrsList (
            lib.mapAttrsToList (
              configName: nixosConfig:
              builtins.addErrorContext "while processing NixOS configuration ${configName}" (
                lib.mergeAttrsList (
                  lib.mapAttrsToList (
                    deviceName: devicePath:
                    builtins.addErrorContext "while constructing outputs for '${deviceName}', '${configName}'" (
                      customLibInstance.images.mkTargetOutputs {
                        name = configName;
                        deviceConfiguration = devicePath;
                        nixosConfiguration = nixosConfig;
                      }
                    )
                  ) devices
                )
              )
            ) self.nixosConfigurations
          );
        in
        builtins.addErrorContext "while constructing packages for system ${system}" mergedPackages
      );
    };
}

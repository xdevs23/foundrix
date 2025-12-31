{
  outputs =
    {
      self,
      nixpkgs,
      foundrix,
      ...
    }@flakeArgs:
    let
      lib = nixpkgs.lib;
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
      foundrixPackages =
        pkgs: extraArgs:
        let
          scope = extraArgs // {
            inherit pkgs;
          };
        in
        lib.filesystem.packagesFromDirectoryRecursive {
          callPackage = pkgs.newScope scope;
          newScope = extra: pkgs.newScope (scope // extra);
          directory = ./packages;
        };
      defaultSpecialArgs = {
        foundrixModules = foundrix.nixosModules;
        foundrixInputs = foundrix.nixosModules.foundrixInputs;
        foundrixIgnoreMissingInputs = false;
        inherit foundrix foundrixPackages;
        inputs = builtins.removeAttrs flakeArgs [ "self" ];
        currentFlake = self;
      }
      // (import ./special.nix {
        inherit lib foundrix;
        currentFlake = self;
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
            recurse = false;
          }
        else
          { };

    in
    {
      nixosModules = {
        foundrixSpecialArgs = defaultSpecialArgs;
      };
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
            ) (self.nixosConfigurations or { })
          );
        in
        builtins.addErrorContext "while constructing packages for system ${system}" mergedPackages
      );
    };
}

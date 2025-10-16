{
  inputs = {
    # Typically this one is used in conjunction with inputs.nixpkgs.follow
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # These two would usually not be overridden as their purpose
    # is to deviate from the main one
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
      defaultSpecialArgs = {
        foundrix = self;
        foundrixModules = self.nixosModules;
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

      # Create a function that partially applies special args to a module
      providePartialArgs =
        module: specialArgs:
        if lib.isFunction module then
          let
            # Get the original function's argument pattern
            originalArgs = lib.functionArgs module;
            # Combine with our special args
            combinedArgs = originalArgs // (lib.mapAttrs (name: value: true) specialArgs);

            # Create a wrapper function that applies the special args
            wrapper = args: (module (args // specialArgs)) // { imports = [ ./common ]; };
          in
          # Set the function args to include both original and special args
          lib.setFunctionArgs wrapper combinedArgs
        else
          module;

      # Process directory recursively, can be used for both module loading and testing
      processDirectoryRecursive =
        directory: extraArgs:
        let
          lib = nixpkgs.lib;
          specialArgs = defaultSpecialArgs // (extraArgs.specialArgs or { });

          processDir =
            dir:
            lib.concatMapAttrs (
              name: type:
              let
                path = dir + "/${name}";
              in
              if type == "directory" then
                { "${name}" = processDir path; }
              else if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix" then
                let
                  baseName = lib.removeSuffix ".nix" name;
                  originalModule = import path;
                in
                if extraArgs ? transformModule then
                  # For tests: transform the module with special args and apply custom function
                  {
                    ${baseName} = extraArgs.transformModule baseName (providePartialArgs originalModule specialArgs);
                  }
                else
                  # For regular module loading: wrap with special args
                  {
                    ${baseName} =
                      { ... }:
                      {
                        imports = [
                          ./common
                          path
                        ];
                        config._module.specialArgs = specialArgs;
                      };
                  }
              else
                { }
            ) (builtins.readDir dir);

        in
        processDir directory;

      modulesFromDirectoryRecursive = directory: processDirectoryRecursive directory { };
      forEachProfileRecursive =
        directory: f:
        processDirectoryRecursive directory {
          transformModule = f;
        };
    in
    {
      nixosConfigurations = {
        default = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = defaultSpecialArgs;
          modules = [
            ./common
            self.nixosModules.profiles.all-modules
            self.nixosModules.profiles.minimal-image
            self.nixosModules.config.debug
            {
              system.forbiddenDependenciesRegexes = lib.mkForce [ ];
            }
          ];
        };
      };
      packages = (
        forAllSystems (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
          in
          (pkgs.lib.filesystem.packagesFromDirectoryRecursive {
            inherit (pkgs) callPackage;
            directory = ./packages;
          })
          // ((customLib system).images.mkTargetOutputs {
            name = "foundrix";
            deviceName = "generic";
            nixosConfiguration = self.nixosConfigurations.default;
          })
        )
      );
      nixosModules =
        lib.attrsets.mergeAttrsList (
          map
            (path: {
              ${baseNameOf path} = if builtins.pathExists path then modulesFromDirectoryRecursive path else { };
            })
            [
              ./components
              ./config
              ./framework
              ./hardware
              ./home
              ./profiles
              ./services
            ]
        )
        // {
          foundrixSpecialArgs = defaultSpecialArgs;
        };
      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        forEachProfileRecursive ./profiles (
          profileName: profile:
          pkgs.testers.runNixOSTest {
            name = "${profileName}-basic";
            nodes.machine = profile;
            testScript = ''
              machine.wait_for_unit("default.target")
            '';
          }
        )
      );
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}

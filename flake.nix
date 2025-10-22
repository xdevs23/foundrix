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
      foundrixPackages = pkgs: (lib.filesystem.packagesFromDirectoryRecursive {
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

      # Collect all .nix files from a directory recursively (except default.nix)
      collectNixFiles =
        dir:
        let
          entries = builtins.readDir dir;
          processEntry =
            name: type:
            let
              path = dir + "/${name}";
            in
            if type == "directory" then
              collectNixFiles path
            else if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix" then
              [ { inherit path name; } ]
            else
              [ ];
        in
        lib.concatLists (lib.mapAttrsToList processEntry entries);

      # Convert a single nix file path to a module with special args
      pathToModule =
        path:
        { ... }:
        {
          imports = [
            ./common
            path
          ];
          config._module.specialArgs = defaultSpecialArgs;
        };

      # Process directory recursively to create nested attribute set of modules
      processDirectoryRecursive =
        directory:
        let
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
                in
                {
                  ${baseName} = pathToModule path;
                }
              else
                { }
            ) (builtins.readDir dir);
        in
        processDir directory;

      modulesFromDirectoryRecursive = directory: processDirectoryRecursive directory;
    in
    {
      nixosConfigurations = {
        smoke-test = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = defaultSpecialArgs;
          modules = [
            ./common
            self.nixosModules.profiles.all-modules
            self.nixosModules.profiles.minimal-image
            self.nixosModules.profiles.minimal-image-ota
            self.nixosModules.config.debug
          ];
        };
        htpc = lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = defaultSpecialArgs;
          modules = [
            ./common
            self.nixosModules.profiles.htpc
            self.nixosModules.profiles.minimal-image
            self.nixosModules.config.debug
          ];
        };
      };
      packages = (
        forAllSystems (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
          in
          (foundrixPackages pkgs)
          // ((customLib system).images.mkTargetOutputs {
            name = "foundrix";
            deviceName = "generic";
            nixosConfiguration = self.nixosConfigurations.smoke-test;
          })
          // ((customLib system).images.mkTargetOutputs {
            name = "htpc";
            deviceName = "generic";
            nixosConfiguration = self.nixosConfigurations.htpc;
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
          profileFiles = collectNixFiles ./profiles;
        in
        lib.listToAttrs (
          map (
            { path, name }:
            let
              profileName = lib.removeSuffix ".nix" name;
            in
            {
              name = "${profileName}-basic";
              value = pkgs.testers.runNixOSTest {
                name = "${profileName}-basic";
                node.specialArgs = defaultSpecialArgs;
                nodes.machine = {
                  imports = [
                    ./common
                    path
                  ];
                };
                testScript = ''
                  machine.wait_for_unit("default.target")
                '';
              };
            }
          ) profileFiles
        )
      );
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}

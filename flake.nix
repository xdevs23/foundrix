{
  inputs = {
    # Typically this one is used in conjunction with inputs.nixpkgs.follow
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # These two would usually not be overridden as their purpose
    # is to deviate from the main one
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    # This one is only used in this flake, thus it does not need "follows"
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = (
    {
      self,
      nixpkgs,
      nixpkgs-stable,
      ...
    }@flakeArgs:
    let
      lib = nixpkgs.lib;

      pluggedInTo = args: flake: lib.recursiveUpdate flake ((import ./plugin.nix).outputs args);

      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
      foundrixPackages =
        pkgs:
        (lib.filesystem.packagesFromDirectoryRecursive {
          inherit (pkgs) callPackage;
          directory = ./packages;
        });
      traverseDirectory = import ./lib/traverse-directory.nix { inherit lib; };

      collectNixFiles =
        dir:
        traverseDirectory {
          directory = dir;
          format = "list";
        };

      # Convert a single nix file path to a module with special args
      pathToModule =
        path:
        { ... }:
        {
          imports = [
            ./common
            path
          ];
          config._module.specialArgs = self.nixosModules.foundrixSpecialArgs;
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

      foundrixNixosModules = lib.attrsets.mergeAttrsList (
        map
          (path: {
            ${baseNameOf path} = if builtins.pathExists path then modulesFromDirectoryRecursive path else { };
          })
          [
            ./components
            ./config
            ./framework
            ./hardware
            ./profiles
            ./services
          ]
      );
    in
    pluggedInTo (flakeArgs // { foundrix = self; }) {
      lib = import ./lib/export.nix;
      nixosConfigurations = {
        smoke-test = lib.nixosSystem {
          specialArgs = self.nixosModules.foundrixSpecialArgs;
          modules = [
            ./common
            self.nixosModules.profiles.all-modules
            self.nixosModules.config.filesystem.root-tmpfs
            self.nixosModules.config.debug
            {
              # Let's just set some default to make nix flake check happy
              # This will be overridden by the platform-specific module
              # in all cases so this can stay here as a no-op
              nixpkgs.hostPlatform = lib.mkOverride 1200 "aarch64-linux";
            }
          ];
        };
      };
      packages = (
        forAllSystems (
          system:
          let
            buildPlatformPkgs = import nixpkgs { inherit system; };
            # Need to use stable pkgs because certifi doesn't build from unstable
            buildPlatformPkgsStable = import nixpkgs-stable { inherit system; };
          in
          (builtins.addErrorContext "while constructing packages for system ${system}" (
            foundrixPackages buildPlatformPkgs
          ))
          // {
            docs =
              let
                collectModules =
                  attrset:
                  let
                    recurse =
                      set:
                      builtins.concatLists (
                        builtins.map (
                          name:
                          let
                            value = set.${name};
                          in
                          if builtins.isAttrs value && !builtins.isFunction value then recurse value else [ value ]
                        ) (builtins.attrNames set)
                      );
                  in
                  recurse attrset;
                eval = lib.nixosSystem {
                  specialArgs = self.nixosModules.foundrixSpecialArgs // {
                    foundrixIgnoreMissingInputs = true;
                  };
                  modules = (
                    collectModules (
                      lib.updateManyAttrsByPath [
                        {
                          path = [ "hardware" ];
                          update = old: builtins.removeAttrs old [ "platform" ];
                        }
                      ] foundrixNixosModules
                    )
                    ++ [
                      ./lib/device-specific.nix
                      {
                        nixpkgs.hostPlatform = system;
                      }
                    ]
                  );
                };
                optionsDoc = buildPlatformPkgsStable.nixosOptionsDoc {
                  options = { inherit (eval.options) foundrix device; };
                };
              in
              buildPlatformPkgsStable.stdenv.mkDerivation {
                dontUnpack = true;
                name = "docs";

                nativeBuildInputs = with buildPlatformPkgsStable; [
                  mkdocs
                  python310Packages.mkdocs-material
                  python310Packages.pygments
                ];

                buildPhase = ''
                  mkdir docs
                  cp ${optionsDoc.optionsCommonMark} "./docs/nixos-options.md"
                  cp ${
                    buildPlatformPkgsStable.writeText "" (
                      builtins.toJSON {
                        site_name = "foundrix Option Documentation";
                      }
                    )
                  } mkdocs.yml
                  mkdocs build
                '';

                installPhase = ''
                  mv site $out
                  mkdir $out/bin
                  cat \
                    ${buildPlatformPkgsStable.writeShellScript "" ""} \
                    <(echo "xdg-open $out/nixos-options/index.html") \
                    > $out/bin/docs
                  chmod +x $out/bin/docs
                '';

                meta.mainProgram = "docs";
              };
          }
        )
      );
      nixosModules = foundrixNixosModules // {
        inherit pluggedInTo;
        foundrixInputs = builtins.removeAttrs flakeArgs [ "self" ];
      };
      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          profileFiles = collectNixFiles ./profiles;
        in
        lib.listToAttrs (
          map (
            { path, name, ... }:
            let
              profileName = lib.removeSuffix ".nix" name;
            in
            {
              name = "${profileName}-basic";
              value = pkgs.testers.runNixOSTest {
                name = "${profileName}-basic";
                node.pkgsReadOnly = false;
                node.specialArgs = self.nixosModules.foundrixSpecialArgs;
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
      templates = {
        desktop-pc = {
          path = ./templates/desktop-pc;
          description = ''
            A flake-based NixOS desktop configuration
            with foundrix fully configured and ready to use.
          '';
        };
        headless = {
          path = ./templates/headless;
          description = ''
            A flake-based NixOS headless configuration
            with foundrix fully configured and ready to use.
            This is for servers and embedded systems like routers and homelabs.
          '';
        };
      };
      inherit (import ./show.nix { nixosModules = foundrixNixosModules; }) list-modules show-modules;
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    }
  );
}

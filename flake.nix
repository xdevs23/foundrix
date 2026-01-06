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

      pluggedInTo =
        args: flake:
        let
          deviceRoots = flake.deviceRoots or [ (args.self + "/devices") ];
          cleanFlake = removeAttrs flake [ "deviceRoots" ];
        in
        lib.recursiveUpdate cleanFlake ((import ./plugin.nix).outputs (args // { inherit deviceRoots; }));

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
      traverseDirectory = import ./lib/traverse-directory.nix { inherit lib; };

      collectNixFiles =
        dir:
        traverseDirectory {
          directory = dir;
          format = "list";
        };

      # Convert a single nix file path to a module with special args
      pathToModule =
        modulePath:
        { ... }:
        {
          imports = [
            ./common
            modulePath
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
                filePath = dir + "/${name}";
              in
              if type == "directory" then
                { "${name}" = processDir filePath; }
              else if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix" then
                let
                  baseName = lib.removeSuffix ".nix" name;
                in
                {
                  ${baseName} = pathToModule filePath;
                }
              else
                { }
            ) (builtins.readDir dir);
        in
        processDir directory;

      modulesFromDirectoryRecursive = directory: processDirectoryRecursive directory;

      foundrixNixosModules = lib.attrsets.mergeAttrsList (
        map
          (dirPath: {
            ${baseNameOf dirPath} = if builtins.pathExists dirPath then modulesFromDirectoryRecursive dirPath else { };
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

      showOutputs = import ./show.nix { nixosModules = foundrixNixosModules; };
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
        smoke-test-server-writable = lib.nixosSystem {
          specialArgs = self.nixosModules.foundrixSpecialArgs;
          modules = [
            ./common
            self.nixosModules.profiles.image.server-writable
            self.nixosModules.config.runtime.repart.var
            self.nixosModules.config.filesystem.root-tmpfs
            self.nixosModules.config.filesystem.nix
            self.nixosModules.config.filesystem.var
            self.nixosModules.config.debug
            {
              nixpkgs.hostPlatform = lib.mkOverride 1200 "x86_64-linux";
              boot.uki.name = "smoke-test";
              foundrix.config.image.device.dataDevice = "/dev/sda";
            }
          ];
        };
        smoke-test-readonly-ab = lib.nixosSystem {
          specialArgs = self.nixosModules.foundrixSpecialArgs;
          modules = [
            ./common
            self.nixosModules.profiles.image.readonly-ab
            self.nixosModules.config.runtime.repart.data
            self.nixosModules.config.filesystem.root-tmpfs
            self.nixosModules.config.filesystem.var
            self.nixosModules.config.filesystem.home-tmpfs
            self.nixosModules.config.debug
            {
              nixpkgs.hostPlatform = lib.mkOverride 1200 "x86_64-linux";
              boot.uki.name = "smoke-test";
              foundrix.config.image.device.dataDevice = "/dev/nvme0n1";
              system.image.version = "1";
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
            foundrixPackages buildPlatformPkgs { pkgsUnstable = buildPlatformPkgs; }
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
                        map (
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
                          update = old: removeAttrs old [ "platform" ];
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
        foundrixInputs = removeAttrs flakeArgs [ "self" ];
      };
      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          profileFiles = collectNixFiles ./profiles;
        in
        lib.listToAttrs (
          map (
            profileFile:
            let
              profileName = lib.removeSuffix ".nix" profileFile.name;
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
                    profileFile.path
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
        server-writable = {
          path = ./templates/server-writable;
          description = ''
            A flake-based NixOS server configuration with disk image support.
            Includes writable btrfs nix store, UEFI+BIOS boot, runtime /var partition,
            and ephemeral root. Ready to deploy to cloud VMs or bare metal servers.
          '';
        };
      };
      inherit (showOutputs) list-modules show-modules;
      show-traits = builtins.mapAttrs (_: nixos: showOutputs.show-traits { inherit (nixos) config options; }) self.nixosConfigurations;
      show-all-traits = builtins.mapAttrs (_: nixos: showOutputs.show-all-traits { inherit (nixos) config options; }) self.nixosConfigurations;
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    }
  );
}

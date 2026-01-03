{
  outputs =
    {
      self,
      nixpkgs,
      foundrix,
      deviceRoots,
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

      # Collect device configurations with the following rules:
      # - foo.nix takes precedence over foo/default.nix
      # - If foo/default.nix exists (and no foo.nix), use foo/ as device and don't recurse
      # - If directory has no default.nix, recurse into it
      # - Skip default.nix files (they're accessed via their parent directory)
      collectDeviceConfigs =
        dir:
        let
          processDir = currentDir: relativePath:
            let
              entries = builtins.readDir currentDir;
              hasDefault = entries ? "default.nix" && entries."default.nix" == "regular";

              # Get all .nix files except default.nix
              nixFiles = lib.filterAttrs (
                name: type:
                type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
              ) entries;

              # Get all subdirectories
              subdirs = lib.filterAttrs (name: type: type == "directory") entries;

              # For each .nix file, create a device entry
              devicesFromFiles = lib.mapAttrsToList (
                name: _:
                let
                  baseName = lib.removeSuffix ".nix" name;
                  attrName = if relativePath == "" then baseName else "${relativePath}-${baseName}";
                in
                { name = attrName; value = currentDir + "/${name}"; }
              ) nixFiles;

              # For each subdirectory:
              # - If sibling .nix exists (e.g., foo.nix for foo/), skip foo/default.nix but still recurse
              # - If default.nix exists in subdir (and no sibling .nix), use it as a device and don't recurse
              # - Otherwise, recurse into it
              devicesFromDirs = lib.concatMap (
                name:
                let
                  siblingNix = "${name}.nix";
                  hasSiblingNix = nixFiles ? ${siblingNix} || (entries ? ${siblingNix} && entries.${siblingNix} == "regular");
                  subdirPath = currentDir + "/${name}";
                  subdirEntries = builtins.readDir subdirPath;
                  subdirHasDefault = subdirEntries ? "default.nix" && subdirEntries."default.nix" == "regular";
                  newRelativePath = if relativePath == "" then name else "${relativePath}-${name}";
                in
                if hasSiblingNix then
                  # foo.nix exists, skip foo/default.nix but still recurse into foo/
                  processDir subdirPath newRelativePath
                else if subdirHasDefault then
                  # foo/default.nix exists (no sibling), use foo/ as device, don't recurse
                  [ { name = newRelativePath; value = subdirPath; } ]
                else
                  # No default.nix, recurse into subdirectory
                  processDir subdirPath newRelativePath
              ) (lib.attrNames subdirs);
            in
            devicesFromFiles ++ devicesFromDirs;

          results = if builtins.pathExists dir then processDir dir "" else [ ];
        in
        lib.listToAttrs results;

    in
    {
      nixosModules = {
        foundrixSpecialArgs = defaultSpecialArgs;
      };
      packages = forAllSystems (
        system:
        let
          devices = lib.mergeAttrsList (map collectDeviceConfigs deviceRoots);
          devicePaths = lib.attrValues devices;
          customLibInstance = customLib system;

          # Flatten configs and devices into a single list for folding
          configList = lib.mapAttrsToList (name: value: {
            configName = name;
            nixosConfig = value;
          }) (self.nixosConfigurations or { });

          # Fold over all (config, device) pairs, threading seen device names
          result = lib.foldl' (
            acc:
            { configName, nixosConfig }:
            builtins.addErrorContext "while processing NixOS configuration ${configName}" (
              lib.foldl' (
                innerAcc:
                devicePath:
                let
                  targetResult = customLibInstance.images.mkTargetOutputs {
                    name = configName;
                    deviceConfiguration = devicePath;
                    nixosConfiguration = nixosConfig;
                    seenDeviceNames = innerAcc.seen;
                  };
                in
                {
                  outputs = innerAcc.outputs // targetResult.outputs;
                  seen = targetResult.seen;
                }
              ) acc devicePaths
            )
          ) { outputs = {}; seen = {}; } configList;

          mergedPackages = result.outputs;
        in
        builtins.addErrorContext "while constructing packages for system ${system}" mergedPackages
      );
    };
}

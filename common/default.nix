{
  config,
  pkgs,
  lib,
  foundrix,
  currentFlake,
  foundrixPackages,
  pkgsUnstable,
  options,
  ...
}:
{
  imports = [
    ./general.nix
    #./upstream-fixes.nix
    ./hardware.nix
    ./nixpkgs.nix
  ];

  options = {
    nixpkgs-unstable = lib.recursiveUpdate options.nixpkgs { overlays.default = [ ]; };
    nixpkgs-master = lib.recursiveUpdate options.nixpkgs { overlays.default = [ ]; };
  };

  config = {
    _module.args.pkgsUnstable = import foundrix.inputs.nixpkgs-unstable {
      inherit (pkgs.stdenv.hostPlatform) system;
      config = config.nixpkgs.config;
      overlays = config.nixpkgs-unstable.overlays;
    };
    _module.args.pkgsMaster = import foundrix.inputs.nixpkgs-master {
      inherit (pkgs.stdenv.hostPlatform) system;
      config = config.nixpkgs.config;
      overlays = config.nixpkgs-master.overlays;
    };
    _module.args.mkConfigurableUsersOption =
      {
        description ? "",
      }:
      lib.mkOption {
        type = with lib.types; nullOr (listOf str);
        default = null;
        inherit description;
      };
    _module.args.usersOrAll =
      users:
      if users == null then
        builtins.filter (name: config.users.users.${name}.isNormalUser) (
          builtins.attrNames config.users.users
        )
      else
        users;
    _module.args.namespacedCfg =
      curPos:
      let
        file = curPos.file;
        foundrixRoot = toString foundrix;
        currentFlakeRoot = toString currentFlake;

        # Check if file is within foundrix
        isInFoundrix = lib.hasPrefix foundrixRoot file;

        root = if isInFoundrix then foundrixRoot else currentFlakeRoot;

        # Get relative path from root
        relPath = builtins.substring (
          builtins.stringLength (toString root) + 1
        ) (builtins.stringLength file) file;

        # Split into parts
        parts = builtins.filter (x: x != "") (lib.splitString "/" relPath);

        # Remove .nix from last element
        fileName = builtins.elemAt parts (builtins.length parts - 1);
        baseName =
          if builtins.match "(.*)\.nix" fileName != null then
            builtins.head (builtins.match "(.*)\.nix" fileName)
          else
            fileName;

        # Build path parts
        dirParts = lib.lists.take (builtins.length parts - 1) parts;
        prefix = if isInFoundrix then [ "foundrix" ] else [ "custom" ];
        allParts = prefix ++ dirParts ++ (if baseName == "default" then [ ] else [ baseName ]);

        # Navigate config path
        getPath =
          cfg: path: if path == [ ] then cfg else getPath cfg.${builtins.head path} (builtins.tail path);
      in
      getPath config allParts;
    _module.args.foundrixPkgs = foundrixPackages pkgs {
      inherit pkgsUnstable;
    };
  };
}

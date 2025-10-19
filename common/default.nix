{
  config,
  inputs,
  pkgs,
  lib,
  foundrix,
  options,
  ...
}:
{
  imports = [
    ./general.nix
  ];

  options = {
    nixpkgs-unstable = options.nixpkgs;
    nixpkgs-master = options.nixpkgs;
  };

  config = {
    _module.args.pkgsUnstable = import inputs.nixpkgs-unstable {
      inherit (pkgs) system;
      config = config.nixpkgs.config;
      overlays = config.nixpkgs-unstable.overlays;
    };
    _module.args.pkgsMaster = import inputs.nixpkgs-master {
      inherit (pkgs) system;
      config = config.nixpkgs.config;
      overlays = config.nixpkgs-master.overlays;
    };
    _module.args.mkConfigurableUsersOption =
      {
        description ? "",
      }:
      lib.mkOption {
        type = with lib.types; listOf str;
        default = builtins.filter (name: config.users.users.${name}.isNormalUser) (
          builtins.attrNames config.users.users
        );
        inherit description;
      };
    _module.args.namespacedCfg =
      curPos:
      let
        file = curPos.file;
        root = "${foundrix}";

        # Get relative path from root
        relPath = builtins.substring (builtins.stringLength root + 1) (builtins.stringLength file) file;

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
        allParts = [ "foundrix" ] ++ dirParts ++ (if baseName == "default" then [ ] else [ baseName ]);

        # Navigate config path
        getPath =
          cfg: path: if path == [ ] then cfg else getPath cfg.${builtins.head path} (builtins.tail path);
      in
      getPath config allParts;
  };
}

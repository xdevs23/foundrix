{
  lib,
  config,
  ...
}:
{
  options = {
    foundrix.nixpkgs = {
      allowedUnfreePackageNames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of unfree package names to allow. Names are matched using lib.getName.";
        example = [
          "slack"
          "vscode"
          "steam"
        ];
      };
    };
  };

  config = lib.mkIf (config.foundrix.nixpkgs.allowedUnfreePackageNames != [ ]) {
    nixpkgs.config.allowUnfreePredicate =
      pkg: builtins.elem (lib.getName pkg) config.foundrix.nixpkgs.allowedUnfreePackageNames;
  };
}

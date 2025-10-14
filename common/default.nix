{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./general.nix
  ];

  config = {
    _module.args.pkgsUnstable = import inputs.nixpkgs-unstable {
      inherit (pkgs) system;
      config = config.nixpkgs.config;
    };
    _module.args.pkgsMaster = import inputs.nixpkgs-master {
      inherit (pkgs) system;
      config = config.nixpkgs.config;
    };
    _module.args.mkConfigurableUsersOption = {
      description ? ""
    }: lib.mkOption {
      type = with lib.types; listOf str;
      default = builtins.filter
        (name: config.users.users.${name}.isNormalUser)
        (builtins.attrNames config.users.users);
      inherit description;
    };
  };
}

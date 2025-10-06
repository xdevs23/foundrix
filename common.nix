{ config, inputs, pkgs, ... }: {
  config = {
    _module.args.pkgsUnstable =
      import inputs.nixpkgs-unstable {
        inherit (pkgs) system;
        config = config.nixpkgs.config;
      };
    _module.args.pkgsMaster =
      import inputs.nixpkgs-master {
        inherit (pkgs) system;
        config = config.nixpkgs.config;
      };
  };
}
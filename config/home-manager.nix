{
  inputs,
  foundrixModules,
  foundrixPackages,
  foundrixInputs,
  ...
}:
{
  imports = [
    foundrixInputs.home-manager.nixosModules.home-manager
  ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs foundrixModules foundrixPackages; };
  };
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];
  _module.args.libHm = foundrixInputs.home-manager.lib;
}

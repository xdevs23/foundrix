{
  inputs,
  foundrixModules,
  foundrixPackages,
  ...
}:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs foundrixModules foundrixPackages; };
  };
}

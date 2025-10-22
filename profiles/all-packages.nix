{
  foundrixPackages,
  pkgs,
  ...
}:
{
  environment.systemPackages = builtins.attrValues (foundrixPackages pkgs);
}

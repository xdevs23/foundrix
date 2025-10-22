{
  foundrixPackages,
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = builtins.attrValues (foundrixPackages pkgs);
  system.stateVersion = lib.mkDefault (builtins.substring 0 5 lib.version);
}

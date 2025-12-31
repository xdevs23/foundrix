{
  foundrixPackages,
  pkgs,
  pkgsUnstable,
  lib,
  ...
}:
{
  environment.systemPackages = builtins.attrValues (foundrixPackages pkgs { inherit pkgsUnstable; });
  system.stateVersion = lib.mkDefault (builtins.substring 0 5 lib.version);
}

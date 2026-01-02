{
  foundrixPackages,
  pkgs,
  pkgsUnstable,
  lib,
  ...
}:
let
  # Recursively collect all derivations from a potentially nested attrset
  collectPackages =
    attrs:
    lib.concatLists (
      lib.mapAttrsToList (
        _: value:
        if lib.isDerivation value then
          [ value ]
        else if lib.isAttrs value then
          collectPackages value
        else
          [ ]
      ) attrs
    );
in
{
  environment.systemPackages = collectPackages (foundrixPackages pkgs { inherit pkgsUnstable; });
  system.stateVersion = lib.mkDefault (builtins.substring 0 5 lib.version);
}

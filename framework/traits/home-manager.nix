# Home Manager traits for cross-module capability announcements.
{
  lib,
  traitTypes,
  ...
}:
{
  options.foundrix.traits.homeManager = {
    method = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (builtins.attrValues traitTypes.homeManager.method));
      default = null;
      description = "Home Manager evaluation method - null means not present";
    };
  };
}

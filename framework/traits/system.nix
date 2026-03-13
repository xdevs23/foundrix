{
  lib,
  traitTypes,
  ...
}:
{
  options.foundrix.traits.system = {
    purpose = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (builtins.attrValues traitTypes.system.purpose));
      default = null;
      description = "System purpose - live systems skip runtime partitioning and persistent storage setup";
    };
  };
}

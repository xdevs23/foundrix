# Cross-module capability announcements via traits.
#
# Traits allow modules to announce characteristics that other modules
# can use to auto-configure sensible defaults. This reduces boilerplate
# in downstream projects by enabling smart defaults based on module combinations.
#
# Design principles:
# - Traits describe characteristics using enums for mutually exclusive states
# - Consumers use `config.foundrix.traits.X or null` for graceful non-existence
# - Modules own their trait announcements
# - Enum constants are available via traitTypes module arg
#
# Example:
#   # In root-tmpfs.nix (announcing):
#   foundrix.traits.filesystem.rootType = traitTypes.filesystem.rootType.volatile;
#
#   # In var.nix (consuming):
#   let
#     rootType = config.foundrix.traits.filesystem.rootType or null;
#     isVolatile = rootType == traitTypes.filesystem.rootType.volatile;
#   in {
#     persistMachineId = lib.mkDefault isVolatile;
#   }
{
  lib,
  traitTypes,
  ...
}:
{
  options.foundrix.traits.filesystem = {
    rootType = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (builtins.attrValues traitTypes.filesystem.rootType));
      default = null;
      description = "Root filesystem type - determines persistence and mutability characteristics";
    };

    readOnlyStore = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Nix store is read-only (erofs) and cannot be modified at runtime";
    };

    varProvisioner = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum (builtins.attrValues traitTypes.filesystem.varProvisioner)
      );
      default = null;
      description = ''
        How the /var data volume is provisioned at runtime. Being an enum,
        importing two provisioning modules at once fails eval with a
        definition conflict — they are mutually exclusive by construction.
      '';
    };
  };
}

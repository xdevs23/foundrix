{
  lib,
  traitTypes,
  ...
}:
{
  options.foundrix.traits.image = {
    updateMethod = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (builtins.attrValues traitTypes.image.updateMethod));
      default = null;
      description = "Image update mechanism - determines partition labeling strategy";
    };

    packedOutsideNix = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "The disk image is packed outside the Nix build. The system does not have an image output";
    };
  };
}

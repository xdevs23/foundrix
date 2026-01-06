# Home Manager traits for cross-module capability announcements.
{
  lib,
  ...
}:
{
  options.foundrix.traits.homeManager = {
    present = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Home Manager module is imported and active";
    };

    prebuilt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Home Manager configurations are pre-built and don't require runtime evaluation";
    };
  };
}

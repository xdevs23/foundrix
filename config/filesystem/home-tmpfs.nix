{
  config,
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
let
  homeManagerPresent = config.foundrix.traits.homeManager.present or false;
in
{
  options = namespaced __curPos {
    size = lib.mkOption {
      type = lib.types.str;
      default = "10%";
      description = "Size of the tmpfs for /home";
    };
    mode = lib.mkOption {
      type = lib.types.str;
      default = "0755";
      description = "Permissions mode for /home";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      fileSystems."/home" = {
        fsType = "tmpfs";
        options = [
          "size=${cfg.size}"
          "mode=${cfg.mode}"
          "noatime"
        ];
        neededForBoot = true;
      };

      # Add home.mount to home-manager setup requirements when home-manager is present
      foundrix.config = lib.optionalAttrs homeManagerPresent {
        home-manager.homeManagerUserSetupRequires = [ "home.mount" ];
      };
    };
}

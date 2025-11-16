{
  lib,
  pkgs,
  foundrixModules,
  namespaced,
  namespacedCfg,
  mkConfigurableUsersOption,
  applyHomeManagerUsers,
  ...
}:
{
  imports = [
    foundrixModules.config.graphics.gtk
    foundrixModules.config.graphics.qt
  ];

  options = namespaced __curPos {
    users = mkConfigurableUsersOption {
      description = "Which users to apply cosmic configuration to. Defaults to all users.";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {

      services.displayManager.cosmic-greeter.enable = lib.mkDefault true;
      services.desktopManager.cosmic.enable = lib.mkDefault true;
      home-manager = applyHomeManagerUsers cfg.users {
        xdg.portal.extraPortals = [
          pkgs.xdg-desktop-portal-cosmic
          pkgs.xdg-desktop-portal-gtk
        ];
        xdg.portal.config = rec {
          common = {
            default = [
              "cosmic"
              "gtk"
            ];
          };
          preferred = common;
        };
      };
    };
}

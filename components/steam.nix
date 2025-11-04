{
  pkgs,
  lib,
  config,
  mkConfigurableUsersOption,
  maybeOr,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    gamemode.enable = lib.mkEnableOption "gamemode" // {
      default = true;
    };
    package = lib.mkOption {
      type = lib.types.package;
      description = "Steam package to use";
      default =
        if config.foundrix.hardware.gpu.usesUnstablePackages then pkgs.unstable.steam else pkgs.steam;
    };
    gamescope.enable = lib.mkEnableOption "gamescope";
    gamescope.session.enable = lib.mkEnableOption "gamescope session";
    gamemode.users = mkConfigurableUsersOption {
      description = "Which users to apply gamemode configuration to. Defaults to all users.";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      programs.gamemode = {
        enable = cfg.gamemode.enable;
      };
      programs.gamescope = {
        enable = cfg.gamescope.enable;
        capSysNice = lib.mkDefault true;
        package =
          if config.foundrix.hardware.gpu.usesUnstablePackages then
            pkgs.unstable.gamescope
          else
            pkgs.gamescope;
      };
      programs.steam = {
        enable = true;
        package = cfg.package;
        gamescopeSession.enable = cfg.gamescope.session.enable;
      };
      users.groups.gamemode.members = maybeOr cfg.gamemode.users [ ];
    };

}

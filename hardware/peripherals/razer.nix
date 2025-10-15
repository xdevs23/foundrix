{
  pkgs,
  mkConfigurableUsersOption,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    users = mkConfigurableUsersOption {
      description = "Which users to apply razer configuration to. Defaults to all users.";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      hardware.openrazer.enable = true;
      hardware.openrazer.users = cfg.users;
      environment.systemPackages = with pkgs.unstable; [
        openrazer-daemon
        polychromatic
      ];
      nixpkgs.overlays = [
        (final: prev: {
          linuxPackagesFor =
            kernel:
            (prev.linuxPackagesFor kernel).extend (
              lpfinal: lpprev: {
                openrazer = (pkgs.unstable.linuxPackagesFor kernel).openrazer;
              }
            );
        })
      ];
    };
}

{
  pkgsUnstable,
  mkConfigurableUsersOption,
  namespaced,
  namespacedCfg,
  usersOrAll,
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
      hardware.openrazer.users = usersOrAll cfg.users;
      environment.systemPackages = with pkgsUnstable; [
        openrazer-daemon
        polychromatic
      ];
      nixpkgs.overlays = [
        (final: prev: {
          linuxPackagesFor =
            kernel:
            (prev.linuxPackagesFor kernel).extend (
              lpfinal: lpprev: {
                openrazer = (pkgsUnstable.linuxPackagesFor kernel).openrazer;
              }
            );
        })
      ];
    };
}

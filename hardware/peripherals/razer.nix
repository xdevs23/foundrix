{
  config,
  pkgs,
  mkConfigurableUsersOption,
  ...
}:
{
  options = {
    foundrix.hardware.peripherals.razer = {
      users = mkConfigurableUsersOption {
        description = "Which users to apply razer configuration to. Defaults to all users.";
      };
    };
  };

  config =
    {
      hardware.openrazer.enable = true;
      hardware.openrazer.users = config.foundrix.hardware.peripherals.razer.users;
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

{
  lib,
  pkgs,
  mkConfigurableUsersOption,
  namespaced,
  namespacedCfg,
  usersOrAll,
  ...
}:
{
  options = namespaced __curPos {
    enable = lib.mkEnableOption ''
      Linux userspace support for Nintendo Switch 2 controllers.

      Initializes the controller into HID mode on plug-in and exposes it as a
      properly-laid-out virtual gamepad via uinput (correct stick orientation,
      analog triggers, full button map). Currently covers the NSO GameCube
      Controller (057e:2073). Pro Controller 2, Joy-Con 2, and rumble are
      planned in the same service.
    '';
    users = mkConfigurableUsersOption {
      description = ''
        Users to add to the 'input' group so they can read events from the
        virtual gamepad the service exposes. Defaults to all normal users.
      '';
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      service = pkgs.callPackage ../../packages/nsw2-service { };
    in
    lib.mkIf cfg.enable {
      # uinput kernel module + /dev/uinput access for the bridge to create the
      # virtual gamepad. Service runs as root so the uinput-group plumbing
      # NixOS sets up here is enough on its own.
      hardware.uinput.enable = true;

      # Read access to /dev/input/event* (including the virtual one we create)
      # for normal users so games can see the gamepad.
      users.groups.input.members = usersOrAll cfg.users;

      environment.systemPackages = [ service ];

      services.udev.extraRules = ''
        # Run the userspace driver when an NS2 controller is plugged in.
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="057e", ATTR{idProduct}=="2073", TAG+="systemd", ENV{SYSTEMD_WANTS}+="nsw2-service.service"
      '';

      systemd.services.nsw2-service = {
        description = "Nintendo Switch 2 controller userspace driver";
        # Long-running: init then HID->uinput bridge until the controller
        # is unplugged. udev re-fires us on the next plug-in.
        serviceConfig = {
          Type = "simple";
          ExecStart = lib.getExe service;
          Restart = "no";
        };
      };
    };
}

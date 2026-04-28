{
  lib,
  foundrixPkgs,
  mkConfigurableUsersOption,
  namespaced,
  namespacedCfg,
  usersOrAll,
  ...
}:
{
  options = namespaced __curPos {
    enable = lib.mkEnableOption "Nintendo Switch 2 GameCube Controller (057e:2073) USB HID support";
    users = mkConfigurableUsersOption {
      description = ''
        Users to add to the 'input' group so they can read events from the
        virtual gamepad exposed by the enabler service. Defaults to all users.
      '';
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      enabler = foundrixPkgs.nsw2-enabler;
    in
    lib.mkIf cfg.enable {
      # /dev/uinput is required for the enabler to create the virtual controller.
      hardware.uinput.enable = true;

      # Grant read access to /dev/input/event* nodes (including the one the
      # enabler creates) to the configured users.
      users.groups.input.members = usersOrAll cfg.users;

      # Make the enabler available on PATH for manual invocation / debugging.
      environment.systemPackages = [ enabler ];

      services.udev.extraRules = ''
        # Permissions on the raw USB + hidraw nodes for the NS2 GameCube Controller.
        SUBSYSTEM=="usb", ATTR{idVendor}=="057e", ATTR{idProduct}=="2073", MODE="0660", GROUP="input"
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2073", MODE="0660", GROUP="input"

        # Start the enabler on plug-in. The service runs for the lifetime of the
        # connection (it also acts as the HID->uinput bridge) and exits cleanly
        # when the controller is unplugged. udev re-triggers it on next plug-in.
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="057e", ATTR{idProduct}=="2073", TAG+="systemd", ENV{SYSTEMD_WANTS}+="nsw2-enable-hid.service"
      '';

      systemd.services.nsw2-enable-hid = {
        description = "Initialize NS2 GameCube Controller and bridge HID to a virtual uinput gamepad";
        # Don't start at boot — udev fires this when the controller is plugged in.
        serviceConfig = {
          Type = "simple";
          ExecStart = "${enabler}/bin/nsw2-enable-hid";
          Restart = "no";
        };
      };
    };
}

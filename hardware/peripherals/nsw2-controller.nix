{
  lib,
  pkgs,
  applyHomeManagerUsers,
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
    dolphin.enable = lib.mkEnableOption ''
      Drop a pre-bound Dolphin GCPad profile into each configured user's
      `~/.config/dolphin-emu/Profiles/GCPad/nsw2-gamecube.ini` (via
      home-manager) so the controller works in Dolphin without manual
      rebinding. Open Controllers -> Configure on a GameCube port and pick
      "nsw2-gamecube" from the Profile dropdown -> Load
    ''
    // {
      default = true;
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      service = pkgs.callPackage ../../packages/nsw2-service { };

      # Pre-bound Dolphin GCPad profile for our virtual gamepad. Axis
      # numbers correspond to evdev axis codes: 0=ABS_X, 1=ABS_Y, 2=ABS_Z,
      # 3=ABS_RX, 4=ABS_RY, 5=ABS_RZ. Y axes use `Axis 1-` / `Axis 4-`
      # for "up" because our service emits Y inverted (kernel gamepad
      # convention). ZR is double-mapped to GameCube's Z trigger because
      # they're the same physical button on this controller.
      dolphinProfile = pkgs.writeText "nsw2-gamecube.ini" ''
        [Profile]
        Device = evdev/0/Nintendo Switch 2 NSO GameCube Controller
        Buttons/A = SOUTH
        Buttons/B = EAST
        Buttons/X = NORTH
        Buttons/Y = WEST
        Buttons/Z = TR2
        Buttons/Start = START
        Main Stick/Up = `Axis 1-`
        Main Stick/Down = `Axis 1+`
        Main Stick/Left = `Axis 0-`
        Main Stick/Right = `Axis 0+`
        C-Stick/Up = `Axis 4-`
        C-Stick/Down = `Axis 4+`
        C-Stick/Left = `Axis 3-`
        C-Stick/Right = `Axis 3+`
        Triggers/L = TL
        Triggers/R = TR
        Triggers/L-Analog = `Axis 2+`
        Triggers/R-Analog = `Axis 5+`
        D-Pad/Up = DPAD_UP
        D-Pad/Down = DPAD_DOWN
        D-Pad/Left = DPAD_LEFT
        D-Pad/Right = DPAD_RIGHT
      '';
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

      # lib.mkIf (not lib.optionalAttrs) here is deliberate — gating with
      # optionalAttrs would force `cfg.dolphin.enable` evaluation during
      # module-arg resolution and recurse through namespacedCfg -> config
      # -> namespacedCfg. mkIf is lazy and defers to module merge time.
      home-manager = lib.mkIf cfg.dolphin.enable (
        applyHomeManagerUsers cfg.users {
          xdg.configFile."dolphin-emu/Profiles/GCPad/nsw2-gamecube.ini".source =
            dolphinProfile;
        }
      );
    };
}

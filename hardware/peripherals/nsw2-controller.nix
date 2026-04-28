{
  lib,
  pkgs,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    enable = lib.mkEnableOption ''
      Linux userspace support for Nintendo Switch 2 controllers.

      Currently sends the proprietary handshake required to switch the NSO
      GameCube Controller (057e:2073) into HID mode on plug-in. Pro Controller 2
      and Joy-Con 2 support is planned in the same service.
    '';
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      service = pkgs.callPackage ../../packages/nsw2-service { };
    in
    lib.mkIf cfg.enable {
      environment.systemPackages = [ service ];

      services.udev.extraRules = ''
        # Run the userspace init handshake when an NS2 controller is plugged in.
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="057e", ATTR{idProduct}=="2073", TAG+="systemd", ENV{SYSTEMD_WANTS}+="nsw2-service.service"
      '';

      systemd.services.nsw2-service = {
        description = "Nintendo Switch 2 controller userspace driver";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe service;
          Restart = "no";
        };
      };
    };
}

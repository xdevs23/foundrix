{ mkPerUserHomeManagerModule, ... }:
{
  imports = [
    (mkPerUserHomeManagerModule __curPos {

      home.sessionVariables = {
        MOZ_ENABLE_WAYLAND = "1";
        MOZ_WAYLAND = "1";
        NIXOS_OZONE_WL = "1";
      };
    })
  ];
}

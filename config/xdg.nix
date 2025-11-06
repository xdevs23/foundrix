{ mkPerUserHomeManagerModule, ... }:
{
  imports = [
    (mkPerUserHomeManagerModule __curPos {
      xdg = {
        enable = true;
        mimeApps.enable = true;
        portal.enable = true;
      };
    })
  ];
}

{ mkPerUserHomeManagerModule, pkgs, ... }:
{
  imports = [
    (mkPerUserHomeManagerModule __curPos rec {
      home.pointerCursor = {
        package = pkgs.rose-pine-cursor;
        gtk.enable = true;
        name = "BreezeX-RosePine-Linux";
        size = 24;
      };
      gtk.cursorTheme = {
        inherit (home.pointerCursor) package name size;
      };
    })
  ];
}

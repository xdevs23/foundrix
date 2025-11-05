{ mkPerUserHomeManagerModule, pkgs, ... }:
{
  imports = [
    (mkPerUserHomeManagerModule __curPos {
      gtk = {
        enable = true;
        gtk3 = {
          extraConfig = {
            gtk-toolbar-style = "GTK_TOOLBAR_ICONS";
            gtk-xft-antialias = 1;
            gtk-xft-hinting = 1;
            gtk-xft-hintstyle = "hintslight";
            gtk-xft-rgba = "rgb";
          };
        };
      };
      xdg.portal.extraPortals = [
        pkgs.xdg-desktop-portal-gtk
      ];
    })
  ];
}

{ mkPerUserHomeManagerModule, pkgs, ... }:
{
  imports = [
    (mkPerUserHomeManagerModule __curPos (
      { config, ... }:
      {
        gtk = {
          enable = true;
          # Pin the legacy default (mirror gtk.theme) so the gtk4.theme warning
          # introduced in 26.05 stays silent without changing behavior.
          gtk4.theme = config.gtk.theme;
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
      }
    ))
  ];
}

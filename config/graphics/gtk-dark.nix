{ foundrixModules, mkPerUserHomeManagerModule, ... }:
{
  imports = [
    foundrixModules.config.graphics.gtk
    (mkPerUserHomeManagerModule __curPos rec {
      gtk = {
        theme = {
          name = "Adwaita-dark";
        };
        gtk2.extraConfig = ''
          gtk-theme-name = "Adwaita"
        '';
        gtk3 = {
          extraConfig = {
            gtk-application-prefer-dark-theme = 1;
          };
        };
      };
      dconf.settings = {
        "org/gnome/desktop/interface" = {
          gtk-theme = gtk.theme.name;
          color-scheme = "prefer-dark";
        };
      };
    })
  ];
}

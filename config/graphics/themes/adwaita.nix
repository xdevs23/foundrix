{
  foundrixModules,
  mkPerUserHomeManagerModule,
  pkgs,
  ...
}:
{
  imports = [
    foundrixModules.config.graphics.gtk
    (mkPerUserHomeManagerModule __curPos rec {
      home.packages = [
        pkgs.gnome-themes-extra
        pkgs.adwaita-icon-theme
        pkgs.adwaita-qt6
      ];
      environment.sessionVariables = {
        GTK_THEME = "Adwaita";
        QT_STYLE_OVERRIDE = "Adwaita";
      };
      gtk = {
        theme = {
          name = "Adwaita";
        };
        gtk2.extraConfig = ''
          gtk-theme-name = "Adwaita"
        '';
        gtk3 = {
          extraConfig = {
            gtk-application-prefer-dark-theme = 0;
          };
        };
      };
      dconf.settings = {
        "org/gnome/desktop/interface" = {
          gtk-theme = gtk.theme.name;
          color-scheme = "prefer-light";
        };
      };
      qt = {
        platformTheme.name = "adwaita";
        style.name = "adwaita";
      };
    })
  ];
}

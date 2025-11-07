{
  foundrixModules,
  mkPerUserHomeManagerModule,
  pkgs,
  ...
}:
{
  imports = [
    foundrixModules.config.graphics.gtk-dark
    (mkPerUserHomeManagerModule __curPos rec {
      home.packages = [
        pkgs.gnome-themes-extra
        pkgs.adwaita-icon-theme
        pkgs.adwaita-qt6
      ];
      home.sessionVariables = {
        GTK_THEME = "Adwaita:dark";
      };
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
      qt = {
        platformTheme.name = "adwaita";
        style.name = "adwaita-dark";
      };
    })
  ];
}

{ pkgs, mkPerUserHomeManagerModule, ... }:
let
  fontName = "Adwaita Sans";
  fontPackage = pkgs.adwaita-fonts;
in
{
  imports = [
    (mkPerUserHomeManagerModule __curPos {
      gtk.font = {
        package = fontPackage;
        name = fontName;
        size = 11;
      };
    })
  ];

  config = {
    fonts = {
      packages = [ fontPackage ];
      fontconfig.defaultFonts = {
        sansSerif = [ fontName ];
        monospace = [ "Adwaita Mono" ];
      };
    };
  };
}

{
  pkgs,
  lib,
  mkPerUserHomeManagerModule,
  namespaced,
  namespacedCfg,
  ...
}:
let
  font = (namespacedCfg __curPos).font;
in
{
  imports = [
    (mkPerUserHomeManagerModule __curPos {
      home.packages = [
        font.package
      ];
      fonts.fontconfig.enable = true;
      programs.alacritty = {
        enable = true;
        settings = {
          bell = {
            duration = 0;
          };
          colors = {
            bright = {
              black = "#212121";
              blue = "#0099ff";
              cyan = "#00a5ab";
              green = "#11ab00";
              magenta = "#9854ff";
              red = "#ff4053";
              white = "#ffffff";
              yellow = "#bf8c00";
            };
            cursor = {
              cursor = "#9ca1aa";
              text = "#fafafa";
            };
            draw_bold_text_with_bright_colors = true;
            normal = {
              black = "#121212";
              blue = "#448AFF";
              cyan = "#00a5ab";
              green = "#00E676";
              magenta = "#9854ff";
              red = "#ff4053";
              white = "#ffffff";
              yellow = "#FDD835";
            };
            primary = {
              background = "#000000";
              bright_foreground = "#fefefe";
              foreground = "#fafafa";
            };
          };
          cursor = {
            style = {
              shape = "Block";
            };
          };
          font = {
            normal = {
              family = font.family;
            };
            size = font.size;
          };
          mouse = {
            bindings = [
              {
                action = "None";
                mouse = "Middle";
              }
            ];
          };
          scrolling = {
            history = 100000;
          };
          window = {
            decorations = "none";
            opacity = 0.8;
            padding = {
              x = 8;
              y = 8;
            };
          };
        };
      };
    })
  ];

  options = namespaced __curPos {
    font = {
      package = lib.mkOption {
        description = "Package providing the terminal font family";
        type = lib.types.package;
        default = pkgs.nerd-fonts.hasklug;
      };
      family = lib.mkOption {
        description = "Terminal font family, spelled the way fontconfig knows it";
        type = lib.types.str;
        default = "Hasklug Nerd Font Mono";
      };
      size = lib.mkOption {
        description = "Terminal font size in points";
        type = lib.types.numbers.positive;
        default = 10.5;
      };
    };
  };
}

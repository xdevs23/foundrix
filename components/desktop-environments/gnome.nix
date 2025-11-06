{
  pkgs,
  lib,
  mkConfigurableUsersOption,
  applyHomeManagerUsers,
  namespaced,
  namespacedCfg,
  foundrixModules,
  ...
}:
{
  imports = [
    foundrixModules.config.graphics.fonts.adwaita-sans
    foundrixModules.config.graphics.gtk
    foundrixModules.config.graphics.qt
  ];

  options = namespaced __curPos {
    users = mkConfigurableUsersOption {
      description = "Which users to apply gnome configuration to. Defaults to all users.";
    };
    useGdm = lib.mkEnableOption "whether to use GDM" // {
      default = true;
    };
    extensions = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
      description = "Extension packages to install and enable";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      home-manager = applyHomeManagerUsers cfg.users {
        xdg.portal.config = {
          common = {
            default = [
              "gnome"
              "gtk"
            ];
          };
        };
        xdg.portal.extraPortals = with pkgs; [
          xdg-desktop-portal-gnome
          xdg-desktop-portal-gtk
        ];
        home.packages = cfg.extensions ++ [
          pkgs.gnome-tweaks
        ];
        dconf = {
          settings."org/gnome/shell" = {
            disable-user-extensions = false;
            enabled-extensions = lib.map (package: package.extensionUuid) cfg.extensions;
          };
        };
      };
      services.gnome.gnome-keyring.enable = true;
      nixpkgs.overlays = [
        (
          final: prev:
          let
            fixSpotify =
              spotify:
              spotify.overrideAttrs (
                finalAttrs: prevAttrs: {
                  fixupPhase =
                    builtins.replaceStrings
                      [
                        ''--add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime=true}}"''
                        ''--add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--enable-features=UseOzonePlatform --ozone-platform=wayland}}"''
                      ]
                      [ "" "" ]
                      prevAttrs.fixupPhase;
                }
              );
          in
          {
            spotify = fixSpotify prev.spotify;
            unstable.spotify = fixSpotify prev.unstable.spotify;
          }
        )
        (final: prev: {
          mattermost-desktop = prev.mattermost-desktop.overrideAttrs (
            finalAttrs: prevAttrs: {
              installPhase =
                builtins.replaceStrings
                  [ "--enable-features" ]
                  [
                    "--disable-features=GlobalShortcutsPortal --enable-features"
                  ]
                  prevAttrs.installPhase;
            }
          );
        })
      ];
    }
    // (lib.optionalAttrs (lib.versionOlder lib.version "25.10") {
      services.xserver = {
        displayManager.gdm.enable = cfg.useGdm;
        desktopManager.gnome.enable = true;
      };
    })
    // (lib.optionalAttrs (lib.versionAtLeast lib.version "25.10") {
      services.desktopManager.gnome.enable = true;
      services.displayManager.gdm.enable = cfg.useGdm;
    });
}

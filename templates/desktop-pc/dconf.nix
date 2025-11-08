{
  lib,
  libHm,
  config,
  applyHomeManagerShared,
  ...
}:
{
  home-manager = applyHomeManagerShared {
    dconf.settings =
      lib.optionalAttrs
        (config.services.desktopManager.gnome.enable or config.services.xserver.desktopManager.gnome.enable)
        (
          with libHm.hm.gvariant;
          {
            "org/gnome/shell/app-switcher" = {
              current-workspace-only = true;
            };
            "org/gnome/shell/window-switcher" = {
              app-icon-mode = "both";
            };
            "org/gnome/mutter" = {
              edge-tiling = true;
              attach-modal-dialogs = false;
              experimental-features = [
                "scale-monitor-framebuffer"
                "xwayland-native-scaling"
              ];
              overlay-key = "Super_L";
              workspaces-only-on-primary = false;
            };
            "org/gnome/desktop/input-sources" = rec {
              show-all-sources = true;
              sources = [
                # If you need to add keyboard layouts to GNOME, this is how you do it.
                #(mkTuple [
                #  "xkb"
                #  "de"
                #])
                (mkTuple [
                  "xkb"
                  "us"
                ])
              ];
              mru-sources = sources;
              per-window = false;
              xkb-options = [
                "terminate:ctrl_alt_bksp"
                "lv3:rwin_switch"
              ];
            };
            "org/gnome/desktop/media-handling" = {
              # Generally, I'd say it's a bad idea to automount or even autorun removable media.
              # Media is mounted when you click on it in the file explorer this way.
              automount = false;
              autorun-never = true;
            };
            # You can also configure GNOME Shell Extensions here.
          }
        );
  };
}

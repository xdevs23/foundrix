{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  inputs,
  mkConfigurableUsersOption,
  applyHomeManagerUsers,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    users = mkConfigurableUsersOption {
      description = "Which users to apply hyprland configuration to. Defaults to all users.";
    };
    monitors = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Monitors to configure, in Hyprland config syntax. By default, it's dynamic.";
    };
    terminal = lib.mkOption {
      type = lib.types.package;
      default = pkgsUnstable.alacritty;
      description = "Default terminal application";
    };
    fileManager = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nautilus;
      description = "Default file manager";
    };
    browser = lib.mkOption {
      type = lib.types.package;
      default = pkgs.librewolf;
      description = "Default web browser";
    };
    wallpaper = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      description = "Wallpaper engine, like wpaperd (you probably want to make a custom package)";
    };
    topbar = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      description = "Topbar package to use (you probably want to make a custom package)";
    };
    execOnce = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Additional exec-once statements";
    };
    mainMod = lib.mkOption {
      type = lib.types.str;
      default = "SUPER";
      description = "Default modifier key (usuallay SUPER)";
    };
    additionalBind = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
    additionalBinde = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
    additionalBindm = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    lib.mkIf
      (lib.asserts.assertMsg (inputs ? hyprland) "Please provide a 'hyprland' input in your flake.nix")

      {
        programs = {
          hyprland =
            let
              system = pkgs.stdenv.targetPlatform.system;
            in
            {
              package = inputs.hyprland.packages.${system}.hyprland;
              portalPackage = inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland;
              xwayland.enable = true;
            };
        };
        systemd.services.greetd.serviceConfig = {
          Type = "idle";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "journal";
          TTYReset = true;
          TTYVHangup = true;
          TTYVTDisallocate = true;
        };
        services.greetd = {
          enable = true;
          settings = {
            default_session = {
              command = "${lib.getExe pkgs.greetd.tuigreet} --time --remember --cmd ${lib.getExe' config.programs.hyprland.package "Hyprland"}";
              user = "greeter";
            };
          };
        };
        home-manager = applyHomeManagerUsers cfg.users {
          xdg.portal.extraPortals = [
            pkgs.xdg-desktop-portal-gtk
            config.programs.hyprland.portalPackage
          ];
          xdg.portal.config = rec {
            common = {
              default = [
                "hyprland"
                "gtk"
              ];
            };
            preferred = common;
          };
          wayland.windowManager.hyprland = {
            enable = true;
            package = config.programs.hyprland.package;
            portalPackage = config.programs.hyprland.portalPackage;
            settings =
              let
                wlPaste = lib.getExe' pkgs.wl-clipboard "wl-paste";
                wlCopy = lib.getExe' pkgs.wl-clipboard "wl-copy";
                cliphist = lib.getExe pkgs.cliphist;
                polkitKdeAgent = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
                polkitAuthAgentScript = pkgs.writeShellScript "polkit-auth-agent" ''
                  while ! "${polkitKdeAgent}"; do
                    sleep 5
                  done
                '';
                loginctl = lib.getExe' pkgs.systemd "loginctl";
                ydotool = lib.getExe pkgs.ydotool;
                hyprshot = lib.getExe pkgs.hyprshot;
                wofi = "wofi";
                playerctl = lib.getExe pkgs.playerctl;
                wpctl = lib.getExe' pkgs.wireplumber "wpctl";
                awk = lib.getExe pkgs.gawk;
              in
              {
                env = [
                  "XCURSOR_SIZE,24"
                  "HYPRCURSOR_SIZE,24"
                  "HYPRCURSOR_THEME,rose-pine-hyprcursor"
                ];
                monitor = cfg.monitors ++ [
                  ",highres,auto,auto"
                ];
                exec-once = [
                  # For text
                  "${wlPaste} --type text --watch ${cliphist} store -max-dedupe-search 40 -max-items 100"
                  # For images
                  "${wlPaste} --type image --watch ${cliphist} store -max-items 100"
                  polkitAuthAgentScript
                ]
                ++ cfg.execOnce;

                input = {
                  kb_layout = builtins.head (lib.strings.splitString "-" config.foundrix.general.keymap);
                  kb_variant = "";
                  kb_model = "";
                  kb_options = "";
                  kb_rules = "";
                  repeat_rate = 32;
                  repeat_delay = 440;
                  follow_mouse = 1;
                  follow_mouse_threshold = 2.0;
                  focus_on_close = 1;

                  touchpad = {
                    natural_scroll = true;
                    drag_lock = true;
                  };

                  sensitivity = 0;
                };
                cursor = {
                  persistent_warps = true;
                  no_warps = true;
                };
                general = {
                  gaps_in = 2;
                  gaps_out = 4;
                  border_size = 2;
                  "col.active_border" = "rgba(00b4e7ee) rgba(00ff99ee) 45deg";
                  "col.inactive_border" = "rgba(606060aa)";
                  layout = "dwindle";
                  resize_on_border = true;
                  extend_border_grab_area = 5;
                  hover_icon_on_border = false;
                  allow_tearing = false;
                };
                decoration = {
                  rounding = 7;

                  blur = {
                    enabled = true;
                    size = 3;
                    passes = 3;
                    noise = 0.01;
                    contrast = 0.92;
                    brightness = 0.92;
                    vibrancy = 0.18;
                    vibrancy_darkness = 0.1;
                  };

                  shadow = {
                    enabled = true;
                    range = 2;
                    render_power = 2;
                    color = "rgba(1a1a1a1a)";
                    color_inactive = "rgba(1a1a1a9a)";
                  };
                };
                animations = {
                  enabled = true;

                  bezier = "myBezier, 0.05, 0.98, 0.56, 1.02";

                  animation = [
                    "windows, 1, 3, myBezier"
                    "windowsOut, 1, 3, default, popin 80%"
                    "border, 1, 8, default"
                    "borderangle, 1, 6, default"
                    "fade, 1, 4, default"
                    "workspaces, 1, 4, default"
                  ];
                };
                dwindle = {
                  pseudotile = false;
                  preserve_split = true;
                };
                gestures = {
                  gesture = [
                    "3, left, workspace, +1" # Swipe left to go to next workspace
                    "3, right, workspace, -1" # Swipe right to go to previous workspace
                    "3, up, fullscreen, maximize" # Swipe up to maximize window
                    "3, down, float" # Swipe down to float/unfloat window
                    "4, down, close" # Swipe down with 4 fingers to close window
                    "3, horizontal, mod: SUPER, move" # Hold Super + swipe to move window
                    "3, vertical, mod: SUPER, resize" # Hold Super + vertical swipe to resize
                  ];
                };
                render = {
                  direct_scanout = 1;
                };
                misc = {
                  force_default_wallpaper = false;
                  new_window_takes_over_fullscreen = 1;
                  middle_click_paste = false;
                  mouse_move_enables_dpms = true;
                  key_press_enables_dpms = true;
                  focus_on_activate = true;
                  allow_session_lock_restore = true;
                  render_unfocused_fps = 240;
                  vfr = true;
                  vrr = true;
                };
                layerrule = [
                  "ignorealpha, topbar"
                  "blur, topbar"
                  "xray on, topbar"
                  "ignorealpha, quickshell"
                  "blur, quickshell"
                  "xray on, quickshell"
                ];
                windowrulev2 = [
                  "float, title:^(Picture-in-Picture)$"
                  "size 640 360, title:^(Picture-in-Picture)$"
                  "float, class:^(org.kde.polkit-kde-authentication-agent.*)$"
                  "noblur, xwayland:1"
                  "suppressevent maximize, class:.*"
                ];
                "$mainMod" = cfg.mainMod;
                "$screenShotDir" = "~/Pictures/Screenshots";
                "$menu" = "${wofi} --gtk-dark --normal-window -i";
                bind = [
                  "$mainMod, Q, killactive,"
                  "$mainMod, V, togglefloating,"
                  "$mainMod, R, exec, $menu --show drun -p 'Search applications…' -M multi-contains -i -O alphabetical"
                  "$mainMod, M, fullscreen, 1"
                  "$mainMod, F, fullscreen, 0"
                  "$mainMod SHIFT, Q, exec, hyprctl kill"
                  "$mainMod, J, togglesplit,"
                  "$mainMod, B, exec, ${lib.getExe cfg.browser}"
                  "$mainMod, E, exec, ${lib.getExe cfg.fileManager}"
                  "$mainMod, T, exec, ${lib.getExe cfg.terminal}"
                  "$mainMod, left, movefocus, l"
                  "$mainMod, right, movefocus, r"
                  "$mainMod, up, movefocus, u"
                  "$mainMod, down, movefocus, d"
                  "$mainMod, 1, workspace, 1"
                  "$mainMod, 2, workspace, 2"
                  "$mainMod, 3, workspace, 3"
                  "$mainMod, 4, workspace, 4"
                  "$mainMod, 5, workspace, 5"
                  "$mainMod, 6, workspace, 6"
                  "$mainMod, 7, workspace, 7"
                  "$mainMod, 8, workspace, 8"
                  "$mainMod, 9, workspace, 9"
                  "$mainMod SHIFT, 1, movetoworkspace, 1"
                  "$mainMod SHIFT, 2, movetoworkspace, 2"
                  "$mainMod SHIFT, 3, movetoworkspace, 3"
                  "$mainMod SHIFT, 4, movetoworkspace, 4"
                  "$mainMod SHIFT, 5, movetoworkspace, 5"
                  "$mainMod SHIFT, 6, movetoworkspace, 6"
                  "$mainMod SHIFT, 7, movetoworkspace, 7"
                  "$mainMod SHIFT, 8, movetoworkspace, 8"
                  "$mainMod SHIFT, 9, movetoworkspace, 9"
                  "$mainMod, L, exec, ${loginctl} lock-session"
                  ''$mainMod SHIFT, V, exec, ${cliphist} list | $menu --dmenu -p "Search clipboard history…" -M multi-contains -i | ${cliphist} decode | ${wlCopy}''
                  ''$mainMod SHIFT, E, exec, ${wlCopy} -c''
                  ''$mainMod SHIFT, P, exec, ${wlCopy} --clear''
                  ''$mainMod+ALT, 9, exec, ps -eo pid,cmd | $menu --dmenu -p "Search process to kill…" -M multi-contains -i | awk '{ print $1 }' | xargs kill -9''
                  ''$mainMod+ALT, 5, exec, ps -eo pid,cmd | $menu --dmenu -p "Search process to terminate…" -M multi-contains -i | awk '{ print $1 }' | xargs kill -9''
                  ''$mainMod+ALT SHIFT, 9, exec, $menu --dmenu -p "Enter process string to kill…" --exec-search --lines 1 -b | xargs pkill -9''
                  ''$mainMod+ALT SHIFT, 5, exec, $menu --dmenu -p "Enter process string to terminate…" --exec-search --lines 1 -b | xargs pkill -9''
                  "$mainMod, mouse_left, workspace, e-1"
                  "$mainMod, mouse_right, workspace, e+1"
                  "ALT SHIFT, KP_Begin, exec, ${ydotool} click C0"
                  "ALT SHIFT, KP_Begin, exec, ${ydotool} click C0"
                  "$mainMod SHIFT, PRINT, exec, ${hyprshot} -m window -m active -o $screenShotDir"
                  "$mainMod, PRINT, exec, ${hyprshot} -m output -o $screenShotDir"
                  ", PRINT, exec, ${hyprshot} -m region -o $screenShotDir"
                  '', XF86AudioRaiseVolume, exec, ${wpctl} set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+''
                  '', XF86AudioLowerVolume, exec, ${wpctl} set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-''
                  '', XF86AudioMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle''
                  '', XF86AudioMicMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle''
                  ''$mainMod SHIFT, M, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle''
                  '', XF86AudioPlay, exec, ${playerctl} play-pause''
                  '', XF86AudioPause, exec, ${playerctl} play-pause''
                  '', XF86AudioStop, exec, ${playerctl} stop''
                  '', XF86AudioPrev, exec, ${playerctl} previous''
                  '', XF86AudioNext, exec, ${playerctl} next''
                  ''$mainMod, mouse_down, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | ${awk} '/^float.*/ {print $2 * 1.1}')''
                  ''$mainMod, mouse_up, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | ${awk} '/^float.*/ {print $2 * 0.9}')''
                  ''$mainMod SHIFT, plus, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | ${awk} '/^float.*/ {print $2 * 1.1}')''

                  ''$mainMod SHIFT, mouse_up, exec, hyprctl -q keyword cursor:zoom_factor 1''
                  ''$mainMod SHIFT, mouse_down, exec, hyprctl -q keyword cursor:zoom_factor 1''
                  ''$mainMod SHIFT, minus, exec, hyprctl -q keyword cursor:zoom_factor 1''
                  ''$mainMod SHIFT, KP_SUBTRACT, exec, hyprctl -q keyword cursor:zoom_factor 1''
                  ''$mainMod SHIFT, 0, exec, hyprctl -q keyword cursor:zoom_factor 1''
                ]
                ++ cfg.additionalBind;
                bindm = [
                  "$mainMod, mouse:272, movewindow"
                  "$mainMod, mouse:273, resizewindow"
                ]
                ++ cfg.additionalBindm;
                binde = [
                  ''$mainMod, equal, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | ${awk} '/^float.*/ {print $2 * 1.1}')''
                  ''$mainMod, minus, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | ${awk} '/^float.*/ {print $2 * 0.9}')''
                  ''$mainMod, KP_ADD, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | ${awk} '/^float.*/ {print $2 * 1.1}')''
                  ''$mainMod, KP_SUBTRACT, exec, hyprctl -q keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor | ${awk} '/^float.*/ {print $2 * 0.9}')''
                ]
                ++ cfg.additionalBinde;
              };
          };
          services.hypridle = {
            enable = true;
            settings =
              let
                brightnessctl = lib.getExe pkgs.brightnessctl;
              in
              {
                general = {
                  after_sleep_cmd = "hyprctl dispatch dpms on";
                  ignore_dbus_inhibit = false;
                  lock_cmd = "pidof hyprlock || hyprlock";
                };

                listener = [
                  {
                    timeout = 120;
                    on-timeout = "${brightnessctl} -s set 10";
                    on-resume = "${brightnessctl} -r";
                  }
                  {
                    timeout = 10;
                    on-timeout = "${brightnessctl} -sd rgb:kbd_backlight set 0";
                    on-resume = "${brightnessctl} -rd rgb:kbd_backlight";
                  }
                  {
                    timeout = 300;
                    on-timeout = "loginctl lock-session";
                  }
                ];
              };
          };
          programs.hyprlock = {
            enable = true;
            settings = {
              background = {
                monitor = "";
                blur_passes = 3;
                blur_size = 7;
                noise = 0.01;
                contrast = 0.96;
                brightness = 0.6;
                vibrancy = 0.1;
                vibrancy_darkness = 0.1;
              };

              label = {
                monitor = "";
                text = "$TIME";
                color = "rgba(255, 255, 255, 0.8)";
                font_size = 64;
                rotate = 0;
                position = "0, 200";
                halign = "center";
                valign = "center";
              };

              input-field = {
                monitor = "";
                size = "200, 48";
                dots_size = "0.2"; # Scale of input-field height, 0.2 - 0.8
                dots_spacing = "0.1"; # Scale of dots' absolute size, 0.0 - 1.0
                dots_center = false;
                dots_rounding = -1; # -1 default circle, -2 follow input-field rounding
                inner_color = "rgb(200, 200, 200)";
                font_color = "rgb(10, 10, 10)";
                fade_on_empty = true;
                fade_timeout = 1000; # Milliseconds before fade_on_empty is triggered.
                placeholder_text = "<i>Input Password...</i>"; # Text rendered in the input box when it's empty.
                hide_input = false;
                rounding = -1; # -1 means complete rounding (circle/oval)
                check_color = "rgb(204, 136, 34)";
                fail_color = "rgb(204, 34, 34)"; # if authentication failed, changes outer_color and fail message color
                fail_text = "<i>$FAIL <b>($ATTEMPTS)</b></i>"; # can be set to empty
                fail_transition = 300; # transition time in ms between normal outer_color and fail_color
                capslock_color = -1;
                numlock_color = -1;
                bothlock_color = -1; # when both locks are active. -1 means don't change outer color (same for above)
                invert_numlock = false; # change color if numlock is off
                swap_font_color = false; # see below

                position = "0, -20";
                halign = "center";
                valign = "center";
              };
            };
          };
          programs.wofi = {
            enable = true;
            package = pkgsUnstable.wofi;
            style = ''
              #outer-box {
                background-color: rgba(0, 0, 0, 0.32);
                padding: 8px;
              }

              window {
                background-color: transparent;
                color: #f8f8f8;
              }

              #input {
                background-color: rgba(0, 0, 0, 0.5);
                border: none;
                outline: none;
                padding: 4px 8px;
                border-radius: 7px;
                margin-bottom: 8px;
                color: #f6f6f6;
              }

              #scroll {
                background-color: rgba(0, 0, 0, 0.5);
                padding: 4px;
                border: none;
                border-radius: 7px;
              }

              #entry {
                padding: 4px 8px;
              }

              #entry:selected {
                background: linear-gradient(45deg, rgba(0,180,231,0.32) 0%, rgba(0,231,180,0.32) 100%);
                border-radius: 3px;
                outline: none;
              }
            '';
          };
          home.sessionVariables = {
            MOZ_ENABLE_WAYLAND = "1";
            MOZ_WAYLAND = "1";
            MOZ_DBUS_REMOTE = "1";
            MOZ_USE_XINPUT2 = "1";
            NIXOS_OZONE_WL = "1";
          };
          services.gnome-keyring.enable = true;
        };
      };
}

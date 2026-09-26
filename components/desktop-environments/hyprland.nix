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
  foundrixModules,
  usersOrAll,
  ...
}:
let
  # The path `namespaced` gives this module's options, read back from the
  # nested set it builds.
  optionPath =
    let
      pathOf = attrs: lib.concatMap (name: [ name ] ++ pathOf attrs.${name}) (lib.attrNames attrs);
    in
    pathOf (namespaced __curPos { });

  # A value Hyprland's Lua functions take: a boolean, number, string, list or
  # table.
  luaValue =
    with lib.types;
    oneOf [
      bool
      int
      float
      str
      (listOf luaValue)
      (attrsOf luaValue)
    ]
    // {
      description = "Lua value";
    };

  bindRecord = lib.types.submodule {
    options = {
      keys = lib.mkOption {
        type = lib.types.str;
        example = "SUPER + SHIFT + S";
        description = ''Hyprland Lua key string: modifiers and key joined with " + ".'';
      };
      action = lib.mkOption {
        type = lib.types.attrTag {
          exec = lib.mkOption {
            type = lib.types.str;
            example = "wl-copy --clear";
            description = "Shell command, run through Hyprland's command dispatcher.";
          };
          lua = lib.mkOption {
            type = lib.types.str;
            example = "hl.dsp.window.drag()";
            description = "Lua expression that evaluates to a dispatcher or a function.";
          };
        };
        description = "What the binding does: exactly one of `exec` or `lua`.";
      };
      flags = lib.mkOption {
        type =
          with lib.types;
          attrsOf (oneOf [
            bool
            int
            str
          ]);
        default = { };
        example = {
          repeating = true;
        };
        description = "Options passed unchanged to Hyprland's bind function, such as `repeating`.";
      };
    };
  };

  monitorRecord = lib.types.submodule {
    freeformType = lib.types.attrsOf luaValue;
    options.output = lib.mkOption {
      type = lib.types.str;
      example = "desc:Vendor Model Serial";
      description = ''
        Output selector: an output name, or `desc:` followed by a description
        prefix. Any further field of Hyprland's monitor function can be set
        next to it.
      '';
    };
  };

  ruleRecords =
    function:
    lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf luaValue);
      default = [ ];
      description = ''
        Additional rules, each in the shape of Hyprland's `${function}`
        function. They apply after the module's own rules, in list order.
      '';
    };
in
{
  imports = [
    foundrixModules.config.graphics.gtk
    foundrixModules.config.graphics.qt
    foundrixModules.config.graphics.wayland
  ]
  ++
    map
      (
        name:
        lib.mkRemovedOptionModule (optionPath ++ [ name ]) ''
          Use additionalBinds with binding records instead. A repeating binding
          sets flags.repeating, and a mouse binding uses the drag or resize
          dispatcher as its lua action.
        ''
      )
      [
        "additionalBind"
        "additionalBinde"
        "additionalBindm"
      ];

  options = namespaced __curPos {
    users = mkConfigurableUsersOption {
      description = "Which users to apply hyprland configuration to. Defaults to all users.";
    };
    monitors = lib.mkOption {
      type = lib.types.listOf monitorRecord;
      default = [ ];
      example = [
        {
          output = "DP-1";
          mode = "2560x1440@144";
          position = "0x0";
          scale = 1;
        }
      ];
      description = ''
        Monitor rules in list order, each in the shape of Hyprland's monitor
        function. Monitors without a rule use their highest resolution, an
        automatic position and scale, and VRR.
      '';
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
    lockscreen = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hyprlock;
      description = "Lockscreen package (e.g. hyprlock or quickshell-lockscreen)";
    };
    execOnce = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Additional commands to run once when Hyprland starts";
    };
    mainMod = lib.mkOption {
      type = lib.types.str;
      default = "SUPER";
      description = ''
        Default modifier: Hyprland Lua modifier names joined with " + ". Key
        strings of bindings are built by joining it with the other keys.
      '';
    };
    menu = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "wofi --gtk-dark --normal-window -i";
      description = "Application menu command the module's bindings use, for building further commands.";
    };
    additionalBinds = lib.mkOption {
      type = lib.types.listOf bindRecord;
      default = [ ];
      example = lib.literalExpression ''
        [
          {
            keys = "SUPER + SHIFT + S";
            action.exec = "hyprshot -m region";
          }
          {
            keys = "SUPER + ALT + mouse:274";
            action.lua = "hl.dsp.window.drag()";
          }
        ]
      '';
      description = "Additional bindings, applied after the module's own bindings.";
    };
    additionalWindowRules = ruleRecords "hl.window_rule";
    additionalLayerRules = ruleRecords "hl.layer_rule";
    additionalWorkspaceRules = ruleRecords "hl.workspace_rule";
    submaps = lib.mkOption {
      type = with lib.types; attrsOf (listOf bindRecord);
      default = { };
      description = ''
        Submaps by name, each with its bindings. A binding whose lua action is
        `hl.dsp.submap("<name>")` enters a submap, and `hl.dsp.submap("reset")`
        leaves it.
      '';
    };
    extraConfig = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Lua text appended after the generated configuration";
    };
    hyprWorkspacedPins = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Window matchers to pin to workspaces (e.g. 'class:Mattermost')";
    };
    hyprWorkspacedOnReconnectRestart = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = "Systemd user service to restart when Hyprland IPC reconnects (e.g. 'quickshell-topbar.service')";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;

      hyprland = pkgsUnstable.hyprland;

      # Workspace daemon for synchronized virtual workspaces across monitors
      hyprWorkspaced = pkgs.callPackage ../../packages/hypr-workspaced { };
      workspaced = lib.getExe hyprWorkspaced;

      wlPaste = lib.getExe' pkgs.wl-clipboard "wl-paste";
      wlCopy = lib.getExe' pkgs.wl-clipboard "wl-copy";
      cliphist = lib.getExe pkgs.cliphist;
      loginctl = lib.getExe' pkgs.systemd "loginctl";
      ydotool = lib.getExe pkgs.ydotool;
      hyprshot = lib.getExe pkgs.hyprshot;
      playerctl = lib.getExe pkgs.playerctl;
      wpctl = lib.getExe' pkgs.wireplumber "wpctl";
      uwsmApp = cmd: "uwsm app -- ${cmd}";
      screenshotDir = "~/Pictures/Screenshots";

      toLua = lib.generators.toLua { };
      inherit (lib.generators) mkLuaInline;

      mod = cfg.mainMod;
      bind = keys: action: {
        inherit keys action;
        flags = { };
      };
      repeating = keys: action: {
        inherit keys action;
        flags.repeating = true;
      };
      exec = command: { exec = command; };
      lua = expression: { lua = expression; };
      focus = direction: lua ''hl.dsp.focus({ direction = "${direction}" })'';
      zoomBy =
        factor:
        lua ''function() hl.config({ cursor = { zoom_factor = hl.get_config("cursor.zoom_factor") * ${factor} } }) end'';
      zoomReset = lua "function() hl.config({ cursor = { zoom_factor = 1 } }) end";

      # The module's own bindings and the extra ones take this one path into
      # Home Manager's argument list for hl.bind.
      renderBind =
        {
          keys,
          action,
          flags,
        }:
        {
          _args = [
            keys
            (mkLuaInline (if action ? exec then "hl.dsp.exec_cmd(${toLua action.exec})" else action.lua))
          ]
          ++ lib.optional (flags != { }) flags;
        };

      binds = [
        (bind "${mod} + Q" (lua "hl.dsp.window.close()"))
        (bind "${mod} + V" (lua "hl.dsp.window.float()"))
        (bind "${mod} + R" (
          exec "${cfg.menu} --show drun -p 'Search applications…' -M multi-contains -i -O alphabetical"
        ))
        (bind "${mod} + M" (lua ''hl.dsp.window.fullscreen({ mode = "maximized" })''))
        (bind "${mod} + F" (lua ''hl.dsp.window.fullscreen({ mode = "fullscreen" })''))
        (bind "${mod} + SHIFT + Q" (exec "hyprctl kill"))
        (bind "${mod} + J" (lua ''hl.dsp.layout("togglesplit")''))
        (bind "${mod} + B" (exec (uwsmApp (lib.getExe cfg.browser))))
        (bind "${mod} + E" (exec (uwsmApp (lib.getExe cfg.fileManager))))
        (bind "${mod} + T" (exec (uwsmApp (lib.getExe cfg.terminal))))
        (bind "${mod} + left" (focus "left"))
        (bind "${mod} + right" (focus "right"))
        (bind "${mod} + up" (focus "up"))
        (bind "${mod} + down" (focus "down"))
        (bind "${mod} + L" (exec "${loginctl} lock-session"))
        (bind "${mod} + C" (exec "${workspaced} collapse invisible"))
        (bind "${mod} + SHIFT + C" (exec "${workspaced} collapse all"))
        (bind "${mod} + I" (exec "${workspaced} swap next"))
        (bind "${mod} + SHIFT + I" (exec "${workspaced} swap prev"))
      ]
      # Dynamic workspace switching and moving (works with any number of monitors)
      ++ map (n: bind "${mod} + ${toString n}" (exec "${workspaced} switch ${toString n}")) (
        lib.range 1 9
      )
      ++ map (n: bind "${mod} + SHIFT + ${toString n}" (exec "${workspaced} move ${toString n}")) (
        lib.range 1 9
      )
      ++ [
        (bind "${mod} + SHIFT + V" (
          exec ''${cliphist} list | ${cfg.menu} --dmenu -p "Search clipboard history…" -M multi-contains -i | ${cliphist} decode | ${wlCopy}''
        ))
        (bind "${mod} + SHIFT + E" (exec "${wlCopy} -c"))
        (bind "${mod} + SHIFT + P" (exec "${wlCopy} --clear"))
        (bind "${mod} + ALT + 9" (
          exec ''ps -eo pid,cmd | ${cfg.menu} --dmenu -p "Search process to kill…" -M multi-contains -i | awk '{ print $1 }' | xargs kill -9''
        ))
        (bind "${mod} + ALT + 5" (
          exec ''ps -eo pid,cmd | ${cfg.menu} --dmenu -p "Search process to terminate…" -M multi-contains -i | awk '{ print $1 }' | xargs kill -9''
        ))
        (bind "${mod} + ALT + SHIFT + 9" (
          exec ''${cfg.menu} --dmenu -p "Enter process string to kill…" --exec-search --lines 1 -b | xargs pkill -9''
        ))
        (bind "${mod} + ALT + SHIFT + 5" (
          exec ''${cfg.menu} --dmenu -p "Enter process string to terminate…" --exec-search --lines 1 -b | xargs pkill -9''
        ))
      ]
      ++ [
        # Mouse side buttons for virtual workspace navigation
        (bind "${mod} + mouse_left" (exec "${workspaced} prev"))
        (bind "${mod} + mouse_right" (exec "${workspaced} next"))
      ]
      ++ [
        (bind "ALT + SHIFT + KP_Begin" (exec "${ydotool} click C0"))
        (bind "ALT + SHIFT + KP_Begin" (exec "${ydotool} click C0"))
        (bind "${mod} + SHIFT + PRINT" (exec "${hyprshot} -m window -m active -o ${screenshotDir}"))
        (bind "${mod} + PRINT" (exec "${hyprshot} -m output -m active -o ${screenshotDir}"))
        (bind "PRINT" (exec "${hyprshot} -m region -o ${screenshotDir}"))
        (bind "XF86AudioRaiseVolume" (exec "${wpctl} set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"))
        (bind "XF86AudioLowerVolume" (exec "${wpctl} set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-"))
        (bind "XF86AudioMute" (exec "${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle"))
        (bind "XF86AudioMicMute" (exec "${wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))
        (bind "${mod} + SHIFT + M" (exec "${wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))
        (bind "XF86AudioPlay" (exec "${playerctl} play-pause"))
        (bind "XF86AudioPause" (exec "${playerctl} play-pause"))
        (bind "XF86AudioStop" (exec "${playerctl} stop"))
        (bind "XF86AudioPrev" (exec "${playerctl} previous"))
        (bind "XF86AudioNext" (exec "${playerctl} next"))
        (bind "${mod} + mouse_down" (zoomBy "1.1"))
        (bind "${mod} + mouse_up" (zoomBy "0.9"))
        (bind "${mod} + SHIFT + plus" (zoomBy "1.1"))

        (bind "${mod} + SHIFT + mouse_up" zoomReset)
        (bind "${mod} + SHIFT + mouse_down" zoomReset)
        (bind "${mod} + SHIFT + minus" zoomReset)
        (bind "${mod} + SHIFT + KP_SUBTRACT" zoomReset)
        (bind "${mod} + SHIFT + 0" zoomReset)
      ]
      ++ [
        (repeating "${mod} + equal" (zoomBy "1.1"))
        (repeating "${mod} + minus" (zoomBy "0.9"))
        (repeating "${mod} + KP_ADD" (zoomBy "1.1"))
        (repeating "${mod} + KP_SUBTRACT" (zoomBy "0.9"))
      ]
      ++ [
        # The drag and resize dispatchers follow the mouse while the keys are held
        (bind "${mod} + mouse:272" (lua "hl.dsp.window.drag()"))
        (bind "${mod} + mouse:273" (lua "hl.dsp.window.resize()"))
      ];

      layerRules =
        map
          (namespace: {
            match.namespace = namespace;
            ignore_alpha = 0;
            blur = true;
            xray = true;
          })
          [
            "topbar"
            "quickshell"
          ];

      windowRules = [
        {
          match.title = "^(Picture-in-Picture)$";
          float = true;
          size = [
            640
            360
          ];
        }
        {
          match.xwayland = true;
          no_blur = true;
        }
        {
          match.class = ".*";
          suppress_event = "maximize";
        }
        {
          match.class = "^(wofi)$";
          stay_focused = true;
        }
      ];

      # The start event fires once per session, while a reload runs the whole
      # configuration again, so start-up commands live in its handler.
      startupCommands = [
        # For text
        "${wlPaste} --type text --watch ${cliphist} store -max-dedupe-search 40 -max-items 100"
        # For images
        "${wlPaste} --type image --watch ${cliphist} store -max-items 100"
      ]
      ++ map uwsmApp cfg.execOnce;
    in
    {
      programs = {
        hyprland = {
          enable = true;
          package = hyprland;
          portalPackage = pkgsUnstable.xdg-desktop-portal-hyprland;
          xwayland.enable = true;
        };
        uwsm = {
          enable = true;
          waylandCompositors.hyprland = {
            prettyName = "Hyprland";
            comment = "Hyprland compositor managed by UWSM";
            binPath = lib.getExe' hyprland "start-hyprland";
            extraArgs = [ "--no-nixgl" ];
          };
        };
      };
      # Portal backend selection must be declared at the NixOS level: the daemon
      # reads portals.conf from /etc/xdg/xdg-desktop-portal/, and NixOS's
      # xdg-desktop-portal patch hard-codes NIX_XDG_DESKTOP_PORTAL_DIR to the
      # system profile, so portals installed via home-manager are invisible
      # (see home-manager#7124). programs.hyprland.enable above registers
      # xdg-desktop-portal-hyprland there; wayland-session.nix adds the gtk portal.
      xdg.portal.config = {
        hyprland.default = [
          "hyprland"
          "gtk"
        ];
        common.default = [ "gtk" ];
      };
      environment.systemPackages = [ pkgs.uwsm ];
      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${lib.getExe pkgs.tuigreet} --time --remember --cmd '${lib.getExe pkgs.uwsm} start hyprland-uwsm.desktop'";
            user = "greeter";
          };
        };
      };
      home-manager = applyHomeManagerUsers cfg.users {
        systemd.user.services.hyprpolkitagent = {
          Unit = {
            Description = "Hyprland Polkit Authentication Agent";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
            ConditionEnvironment = "WAYLAND_DISPLAY";
          };
          Service = {
            ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
            Slice = "session.slice";
            Restart = "on-failure";
            TimeoutStopSec = "5sec";
            # adwaita-qt's QT_STYLE_OVERRIDE is a widget-only style name, but
            # QtQuickControls2 tries to import it as a QML module and crashes
            # the agent's dialog (QTBUG-99889). Scrub it for this unit only.
            UnsetEnvironment = "QT_STYLE_OVERRIDE QT_QPA_PLATFORMTHEME";
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
        systemd.user.services.hypr-workspaced = {
          Unit = {
            Description = "Hyprland workspace daemon for synchronized virtual workspaces";
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "notify";
            ExecStart =
              "${workspaced} daemon"
              + lib.optionalString (
                cfg.hyprWorkspacedOnReconnectRestart != null
              ) " --on-hypr-ipc-reconnect-restart ${cfg.hyprWorkspacedOnReconnectRestart}";
            ExecStartPost = [
              "${workspaced} assign"
            ]
            ++ map (pin: "${workspaced} pin ${pin}") cfg.hyprWorkspacedPins;
            Restart = "on-failure";
            RestartSec = 1;
          };
          Install = {
            WantedBy = [ "graphical-session.target" ];
          };
        };
        wayland.windowManager.hyprland = {
          enable = true;
          package = config.programs.hyprland.package;
          portalPackage = config.programs.hyprland.portalPackage;
          systemd.enable = false; # Conflicts with UWSM
          extraConfig = cfg.extraConfig;
          settings = {
            env = map (variable: { _args = variable; }) [
              [
                "XDG_CURRENT_DESKTOP"
                "Hyprland"
              ]
              [
                "XCURSOR_SIZE"
                "24"
              ]
              [
                "HYPRCURSOR_SIZE"
                "24"
              ]
              [
                "HYPRCURSOR_THEME"
                "rose-pine-hyprcursor"
              ]
            ];
            monitor = cfg.monitors ++ [
              {
                output = "";
                mode = "highres";
                position = "auto";
                scale = "auto";
                vrr = 1;
              }
            ];
            on._args = [
              "hyprland.start"
              (mkLuaInline (
                "function()\n"
                + lib.concatMapStrings (command: "  hl.exec_cmd(${toLua command})\n") startupCommands
                + "end"
              ))
            ];

            config = {
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
                  drag_lock = 1;
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
                col = {
                  active_border = {
                    colors = [
                      "rgba(00b4e7ee)"
                      "rgba(00ff99ee)"
                    ];
                    angle = 45;
                  };
                  inactive_border = "rgba(606060aa)";
                };
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
              animations.enabled = true;
              dwindle = {
                # dwindle:pseudotile was removed in Hyprland 0.55 (it was a
                # no-op); setting it now errors on config parse.
                preserve_split = true;
              };
              render = {
                direct_scanout = 1;
              };
              misc = {
                force_default_wallpaper = 0;
                on_focus_under_fullscreen = 1;
                middle_click_paste = false;
                mouse_move_enables_dpms = true;
                key_press_enables_dpms = true;
                focus_on_activate = true;
                allow_session_lock_restore = true;
                render_unfocused_fps = 240;
                vrr = 1;
              };
            };

            curve._args = [
              "myBezier"
              {
                type = "bezier";
                points = [
                  [
                    0.05
                    0.98
                  ]
                  [
                    0.56
                    1.02
                  ]
                ];
              }
            ];
            animation = [
              {
                leaf = "windows";
                enabled = true;
                speed = 3;
                bezier = "myBezier";
              }
              {
                leaf = "windowsMove";
                enabled = true;
                speed = 3;
                bezier = "myBezier";
              }
              {
                leaf = "windowsOut";
                enabled = true;
                speed = 3;
                bezier = "default";
                style = "popin 80%";
              }
              {
                leaf = "border";
                enabled = true;
                speed = 8;
                bezier = "default";
              }
              {
                leaf = "borderangle";
                enabled = true;
                speed = 6;
                bezier = "default";
              }
              {
                leaf = "fade";
                enabled = true;
                speed = 4;
                bezier = "default";
              }
              {
                leaf = "workspaces";
                enabled = true;
                speed = 4;
                bezier = "default";
              }
            ];
            gesture = [
              # Swipe up to maximize window
              {
                fingers = 3;
                direction = "up";
                action = "fullscreen";
                mode = "maximize";
              }
              # Swipe down to float/unfloat window
              {
                fingers = 3;
                direction = "down";
                action = "float";
              }
              # Swipe down with 4 fingers to close window
              {
                fingers = 4;
                direction = "down";
                action = "close";
              }
              # Hold Super + swipe to move window
              {
                fingers = 3;
                direction = "horizontal";
                mods = "SUPER";
                action = "move";
              }
              # Hold Super + vertical swipe to resize
              {
                fingers = 3;
                direction = "vertical";
                mods = "SUPER";
                action = "resize";
              }
              # Workspace swipe gestures (only affects current monitor, not synchronized)
              {
                fingers = 3;
                direction = "left";
                action = "workspace";
              }
              {
                fingers = 3;
                direction = "right";
                action = "workspace";
              }
            ];
            layer_rule = layerRules ++ cfg.additionalLayerRules;
            window_rule = windowRules ++ cfg.additionalWindowRules;
            workspace_rule = cfg.additionalWorkspaceRules;
            bind = map renderBind (binds ++ cfg.additionalBinds);
          };
          submaps = lib.mapAttrs (_: submapBinds: {
            settings.bind = map renderBind submapBinds;
          }) cfg.submaps;
        }
        # Home Manager writes the settings above as a Hyprland Lua
        # configuration, one Lua call per attribute.
        // lib.optionalAttrs (lib.versionAtLeast lib.version "26.04") {
          configType = "lua";
        };
        services.hypridle = {
          enable = true;
          settings =
            let
              brightnessctl = lib.getExe pkgs.brightnessctl;
            in
            {
              general = {
                after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'";
                ignore_dbus_inhibit = false;
                lock_cmd = lib.getExe cfg.lockscreen;
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
          MOZ_DBUS_REMOTE = "1";
          MOZ_USE_XINPUT2 = "1";
        };
        home.packages = [
          hyprWorkspaced
          pkgs.cava
          inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default
        ];
        services.gnome-keyring.enable = true;
      };
    };
}

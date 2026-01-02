{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;
  steamCfg = config.programs.steam;

  # Get extra compat tools paths from the system steam config
  extraCompatPaths = lib.makeSearchPathOutput "steamcompattool" "" (steamCfg.extraCompatPackages or [ ]);

  # MangoHud config file for mangoapp
  mangoConfigFile = pkgs.writeText "mangohud.conf" cfg.mangoConfig;

  defaultGamescopePackage =
    if config.foundrix.hardware.gpu.usesUnstablePackages or false then
      pkgsUnstable.gamescope
    else
      pkgs.gamescope;

  # Detect best monitor: highest resolution, then highest refresh rate
  detectBestMonitor = pkgs.writeShellScript "detect-best-monitor" ''
    best=""
    best_pixels=0

    for conn in /sys/class/drm/card*-*; do
      [[ -d "$conn" ]] || continue
      status=$(${lib.getExe' pkgs.coreutils "cat"} "$conn/status" 2>/dev/null)
      [[ "$status" == "connected" ]] || continue

      # Extract connector name (e.g., DP-1 from card0-DP-1)
      name=$(${lib.getExe' pkgs.coreutils "basename"} "$conn" | ${lib.getExe' pkgs.gnused "sed"} 's/card[0-9]*-//')

      # Read first mode (highest/preferred resolution)
      if [[ -f "$conn/modes" ]]; then
        mode=$(${lib.getExe' pkgs.coreutils "head"} -n1 "$conn/modes")
        if [[ "$mode" =~ ^([0-9]+)x([0-9]+) ]]; then
          w="''${BASH_REMATCH[1]}"
          h="''${BASH_REMATCH[2]}"
          pixels=$((w * h))
          if (( pixels > best_pixels )); then
            best="$name"
            best_pixels=$pixels
          fi
        fi
      fi
    done

    if [[ -n "$best" ]]; then
      echo "$best"
    else
      echo "*"
    fi
  '';

  gamescopeArgs = lib.cli.toGNUCommandLineShell { } (
    {
      fullscreen = true;
      steam = true;
      xwayland-count = 2;
      hide-cursor-delay = 3000;
      # Refresh rate settings
      r = cfg.refreshRate; # nested refresh rate
      o = cfg.refreshRate; # unfocused refresh rate
    }
    // lib.optionalAttrs cfg.hdr.enable {
      hdr-enabled = true;
      hdr-itm-enabled = true;
      hdr-sdr-content-nits = cfg.hdr.sdrContentNits;
    }
    // lib.optionalAttrs cfg.mangoapp { mangoapp = true; }
    // lib.optionalAttrs cfg.adaptiveSync { adaptive-sync = true; }
    // lib.optionalAttrs cfg.immediateFlips { immediate-flips = true; }
    // lib.optionalAttrs cfg.exposeWayland { expose-wayland = true; }
    // lib.optionalAttrs cfg.realtimeScheduling { rt = true; }
    // lib.optionalAttrs (cfg.sdrGamutWideness != null) { sdr-gamut-wideness = cfg.sdrGamutWideness; }
  );

  # The actual gamescope session command (run by greetd as the user)
  gamescope-session-run = pkgs.writeShellScript "gamescope-session-run" ''
    export SDL_VIDEODRIVER=wayland
    export XDG_SESSION_TYPE=wayland
    export DXVK_LOG_LEVEL=none
    export STEAM_GAMESCOPE_SESSION=1
    export STEAM_USE_DYNAMIC_VRS=1

    # Steam compatibility tools from system config
    ${lib.optionalString (extraCompatPaths != "") ''export STEAM_EXTRA_COMPAT_TOOLS_PATHS="${extraCompatPaths}"''}

    # Gamescope/gaming optimizations
    export ENABLE_GAMESCOPE_WSI=${if cfg.gamescopeWsi then "1" else "0"}
    export QT_QPA_PLATFORM=xcb
    export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
    export GAMESCOPE_NV12_COLORSPACE=k_EStreamColorspace_BT601
    export VKD3D_SWAPCHAIN_LATENCY_FRAMES=3
    export WINEDLLOVERRIDES=dxgi=n
    export vk_xwayland_wait_ready=false
    export GAMESCOPE_DISABLE_ASYNC_FLIPS=1

    # HDR support for games (DXVK/VKD3D)
    # Note: Do NOT set ENABLE_HDR_WSI=1 with gamescope - it conflicts
    # Gamescope handles HDR itself, we only need DXVK_HDR for games
    ${lib.optionalString cfg.hdr.enable ''
    export DXVK_HDR=1
    ''}

    # Mangoapp configuration (disable vulkan layer, use gamescope's mangoapp)
    ${lib.optionalString cfg.mangoapp ''
    export DISABLE_MANGOHUD=1
    export MANGOHUD_CONFIGFILE="${mangoConfigFile}"
    ''}

    # NTSync for smoother games (requires kernel module)
    ${lib.optionalString cfg.ntSync ''
    export PROTON_USE_NTSYNC=1
    ''}

    # Disable AMD Anti-Lag (causes issues with FSR4 and stuttering per CachyOS)
    export ENABLE_LAYER_MESA_ANTI_LAG=0

    # Disable Steam Overlay to fix ~24 min lag bomb
    ${lib.optionalString cfg.disableSteamOverlay ''
    export LD_PRELOAD=""
    ''}

    # Cursor theme
    export XCURSOR_PATH=${pkgs.rose-pine-cursor}/share/icons
    export XCURSOR_THEME=BreezeX-RosePine-Linux
    export XCURSOR_SIZE=24

    # Create sockets for gamescope communication
    tmpdir=$(${lib.getExe' pkgs.coreutils "mktemp"} -p "$XDG_RUNTIME_DIR" -d -t gamescope.XXXXXXX)
    socket="$tmpdir/startup.socket"
    stats="$tmpdir/stats.pipe"
    export GAMESCOPE_STATS="$stats"
    ${lib.getExe' pkgs.coreutils "mkfifo"} -- "$stats"
    ${lib.getExe' pkgs.coreutils "mkfifo"} -- "$socket"

    # Detect best monitor
    preferred_output=$(${detectBestMonitor})

    /run/wrappers/bin/gamescope \
      ${gamescopeArgs} \
      ${lib.escapeShellArgs cfg.extraArgs} \
      --prefer-output "$preferred_output" \
      -R "$socket" -T "$stats" &
    gamescope_pid="$!"

    # Wait for gamescope to be ready
    if read -r -t 10 response_x_display response_wl_display <>"$socket"; then
      export DISPLAY="$response_x_display"
      export GAMESCOPE_WAYLAND_DISPLAY="$response_wl_display"
    else
      ${lib.getExe' pkgs.coreutils "kill"} -9 "$gamescope_pid" 2>/dev/null || true
      wait "$gamescope_pid" 2>/dev/null || true
      ${lib.getExe' pkgs.coreutils "rm"} -rf "$tmpdir"
      exit 1
    fi

    # Launch Steam
    ${lib.getExe cfg.steamPackage} ${lib.escapeShellArgs cfg.steamArgs}

    # Cleanup
    ${lib.getExe' pkgs.coreutils "kill"} "$gamescope_pid" 2>/dev/null || true
    wait "$gamescope_pid" 2>/dev/null || true
    ${lib.getExe' pkgs.coreutils "rm"} -rf "$tmpdir"
  '';

  # Script to write target user (runs as root via sudo)
  write-gamescope-user = pkgs.writeShellScript "write-gamescope-user" ''
    user="$1"
    if ${lib.getExe' pkgs.coreutils "id"} "$user" &>/dev/null; then
      echo "$user" > /run/gamescope-session-user
    else
      echo "Invalid user: $user" >&2
      exit 1
    fi
  '';

  # Generate greetd config for auto-login to gamescope
  gamescope-greetd-config = pkgs.writeShellScript "gamescope-greetd-config" ''
    GSUSER=$(${lib.getExe' pkgs.coreutils "cat"} /run/gamescope-session-user)
    ${lib.getExe' pkgs.coreutils "cat"} > /run/gamescope-greetd.toml <<EOF
    [terminal]
    vt = 7

    [initial_session]
    command = "${gamescope-session-run}"
    user = "$GSUSER"

    [default_session]
    command = "${gamescope-session-run}"
    user = "$GSUSER"
    EOF
  '';

  # Wrapper that generates config and runs greetd
  gamescope-session-wrapper = pkgs.writeShellScript "gamescope-session-wrapper" ''
    set -euo pipefail
    ${gamescope-greetd-config}
    ${lib.getExe' pkgs.kbd "chvt"} 7
    exec ${lib.getExe pkgs.greetd} --config /run/gamescope-greetd.toml
  '';

  # Implementation scripts for session switching (run via user services to survive DM stop)
  gamescope-switch-impl = pkgs.writeShellScriptBin "gamescope-switch-impl" ''
    set -euo pipefail
    /run/wrappers/bin/sudo ${write-gamescope-user} "$USER"
    ${lib.getExe' pkgs.systemd "systemctl"} stop display-manager.service
    ${lib.getExe' pkgs.systemd "systemctl"} start gamescope-session.service || \
      ${lib.getExe' pkgs.systemd "systemctl"} start gamescope-session-recovery.service
  '';

  desktop-switch-impl = pkgs.writeShellScriptBin "desktop-switch-impl" ''
    set -euo pipefail
    ${lib.getExe' pkgs.systemd "systemctl"} start gamescope-session-recovery.service
  '';

  # User-facing commands
  switch-to-gamemode = pkgs.writeShellScriptBin "switch-to-gamemode" ''
    ${lib.getExe' pkgs.systemd "systemctl"} --user start gamescope-switch.service
  '';

  steamos-session-select = pkgs.writeShellScriptBin "steamos-session-select" ''
    # Steam calls this to switch sessions (requires -steamos3 flag)
    session="''${1:-gamescope}"

    if [[ "$session" == "plasma" ]] || [[ "$session" == "desktop" ]]; then
      # Shutdown Steam gracefully
      ${lib.getExe cfg.steamPackage} -shutdown &
      # Wait briefly for Steam to close
      ${lib.getExe' pkgs.coreutils "sleep"} 2
      # Trigger recovery to return to desktop
      ${lib.getExe' pkgs.systemd "systemctl"} start gamescope-session-recovery.service
    fi
  '';

  gamemode-desktop-entry = pkgs.makeDesktopItem {
    name = "gamescope-session";
    desktopName = "Game Mode";
    comment = "Switch to Steam Big Picture (Gamescope)";
    exec = lib.getExe switch-to-gamemode;
    icon = "steam";
    categories = [ "Game" ];
  };
in
{
  options = namespaced __curPos {
    enable = lib.mkEnableOption "gamescope session switching";

    steamPackage = lib.mkOption {
      type = lib.types.package;
      description = "Steam package to use";
      default =
        if config.foundrix.hardware.gpu.usesUnstablePackages or false then
          pkgsUnstable.steam
        else
          pkgs.steam;
    };

    gamescopePackage = lib.mkOption {
      type = lib.types.package;
      description = "Gamescope package to use";
      default = defaultGamescopePackage;
    };

    hdr.enable = lib.mkOption {
      type = lib.types.bool;
      description = "Enable HDR output (requires Gamescope WSI layer and HDR display)";
      default = false;
    };

    hdr.sdrContentNits = lib.mkOption {
      type = lib.types.int;
      description = "Brightness for SDR content in HDR mode (nits)";
      default = 400;
    };

    refreshRate = lib.mkOption {
      type = lib.types.int;
      description = "Target refresh rate for gamescope output";
      default = 60;
    };

    mangoapp = lib.mkOption {
      type = lib.types.bool;
      description = "Enable gamescope's built-in mangoapp overlay";
      default = true;
    };

    mangoConfig = lib.mkOption {
      type = lib.types.lines;
      description = "MangoHud configuration (one option per line)";
      default = ''
        cpu_temp
        gpu_temp
        gpu_mem_temp
        cpu_mhz
        gpu_power
        background_alpha=0.25
        font_size=20
        gpu_core_clock
        gpu_junction_temp
        gpu_mem_clock
        vram
        throttling_status
        round_corners=13.0
        hud_compact
        frame_timing=0
      '';
    };

    sdrGamutWideness = lib.mkOption {
      type = lib.types.nullOr lib.types.float;
      description = "SDR gamut wideness (0.0-1.0) for color vibrancy. null to disable.";
      default = null;
    };

    adaptiveSync = lib.mkOption {
      type = lib.types.bool;
      description = "Enable adaptive sync (VRR) if available";
      default = true;
    };

    immediateFlips = lib.mkOption {
      type = lib.types.bool;
      description = "Enable immediate flips for lower latency (may cause tearing)";
      default = true;
    };

    exposeWayland = lib.mkOption {
      type = lib.types.bool;
      description = "Expose Wayland socket to games (for native Wayland games)";
      default = true;
    };

    realtimeScheduling = lib.mkOption {
      type = lib.types.bool;
      description = "Use realtime scheduling for smoother gameplay (requires CAP_SYS_NICE)";
      default = true;
    };

    gamescopeWsi = lib.mkOption {
      type = lib.types.bool;
      description = "Enable Gamescope WSI layer (disable if games have video playback issues)";
      default = true;
    };

    ntSync = lib.mkOption {
      type = lib.types.bool;
      description = "Use NTSync instead of WineSync for smoother games (requires kernel support)";
      default = true;
    };

    disableSteamOverlay = lib.mkOption {
      type = lib.types.bool;
      description = "Disable Steam Overlay (fixes ~24 min lag bomb issue)";
      default = true;
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Additional arguments to pass to gamescope";
      default = [ ];
    };

    steamArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Arguments to pass to Steam";
      default = [
        "-steamos3"
        "-gamepadui"
        "-pipewire-dmabuf"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      switch-to-gamemode
      steamos-session-select
      gamemode-desktop-entry
    ];

    # Add steamos-session-select to Steam's FHS environment so Steam can find it
    programs.steam.extraPackages = [ steamos-session-select ];

    # Gamescope session runs its own greetd instance for proper PAM/logind session
    systemd.services.gamescope-session = {
      description = "Gamescope Gaming Session";
      conflicts = [ "display-manager.service" ];
      after = [
        "systemd-user-sessions.service"
        "sound.target"
        "network.target"
      ];
      # If gamescope fails, return to desktop
      onFailure = [ "gamescope-session-recovery.service" ];

      serviceConfig = {
        Type = "idle";
        ExecStart = gamescope-session-wrapper;
        Restart = "no";
        # TTY setup for proper output
        TTYPath = "/dev/tty7";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "journal";
        # Clean up temp files on stop (normal or failed)
        ExecStopPost = "${lib.getExe' pkgs.coreutils "rm"} -f /run/gamescope-session-user /run/gamescope-greetd.toml";
      };
    };

    # Recovery service to return to desktop if gamescope fails
    systemd.services.gamescope-session-recovery = {
      description = "Recover from failed Gamescope session";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "gamescope-session-recover" ''
          ${lib.getExe' pkgs.systemd "systemctl"} stop gamescope-session.service || true
          ${lib.getExe' pkgs.procps "pkill"} -9 gamescope || true

          # Reset HDR state on monitors using proptest
          for driver in amdgpu xe i915; do
            ${lib.getExe' pkgs.libdrm "proptest"} -M "$driver" -D /dev/dri/card* 2>/dev/null | \
              ${lib.getExe pkgs.gawk} '
                /^Connector [0-9]+/ { connector = $2 }
                /HDR_OUTPUT_METADATA/ { print connector, $1 }
              ' | while read -r connector prop_id; do
                if [ -n "$connector" ] && [ -n "$prop_id" ]; then
                  ${lib.getExe' pkgs.libdrm "proptest"} -M "$driver" -D /dev/dri/card* "$connector" connector "$prop_id" 0 2>/dev/null || true
                fi
              done
          done

          ${lib.getExe' pkgs.kbd "chvt"} 1
          ${lib.getExe' pkgs.systemd "systemctl"} restart display-manager.service
        '';
      };
    };

    systemd.user.services.gamescope-switch = {
      description = "Switch to Gamescope Session";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        ExecStart = lib.getExe gamescope-switch-impl;
      };
    };

    systemd.user.services.desktop-switch = {
      description = "Switch back to Desktop Session";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        ExecStart = lib.getExe desktop-switch-impl;
      };
    };

    security.polkit.extraConfig =
      let
        # Find all services that alias to display-manager.service
        dmServices = lib.filter
          (name: lib.elem "display-manager.service" (config.systemd.services.${name}.aliases or [ ]))
          (lib.attrNames config.systemd.services);
        # Build list: gamescope-session + display-manager + all actual DM services + recovery
        allowedUnits = [ "gamescope-session" "gamescope-session-recovery" "display-manager" ] ++ dmServices;
        # Generate JS array for polkit
        unitsArray = lib.concatMapStringsSep ", " (u: ''"${u}.service"'') allowedUnits;
      in
      ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              subject.isInGroup("users") && subject.local) {
            var unit = action.lookup("unit");
            var allowed = [${unitsArray}];
            if (allowed.indexOf(unit) >= 0) {
              return polkit.Result.YES;
            }
          }
        });
      '';

    security.sudo.extraRules = [
      {
        groups = [ "users" ];
        commands = [
          {
            command = "${write-gamescope-user}";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    # Use programs.gamescope which sets up security wrapper with cap_sys_nice
    programs.gamescope = {
      enable = true;
      capSysNice = lib.mkDefault true;
      package = lib.mkDefault cfg.gamescopePackage;
    };

    # Enable libinput for input device support
    services.libinput.enable = true;

    # Graphics setup
    hardware.graphics = {
      enable = lib.mkDefault true;
      enable32Bit = lib.mkDefault true;
      # Gamescope WSI layer for HDR and other features
      extraPackages = [ pkgs.gamescope-wsi ];
      extraPackages32 = [ pkgs.pkgsi686Linux.gamescope-wsi ];
    };

    # Steam hardware support (controllers, etc.)
    hardware.steam-hardware.enable = lib.mkDefault true;

    boot.kernel.sysctl."vm.max_map_count" = lib.mkForce 2147483642;

    # Load NTSync kernel module for smoother Wine/Proton sync
    boot.kernelModules = lib.mkIf cfg.ntSync [ "ntsync" ];
  };
}

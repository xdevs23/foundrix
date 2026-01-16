{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  namespaced,
  namespacedCfg,
  foundrixModules,
  ...
}:
let
  cfg = namespacedCfg __curPos;
  steamCfg = config.programs.steam;

  # Get extra compat tools paths from the system steam config
  extraCompatPaths = lib.makeSearchPathOutput "steamcompattool" "" (
    steamCfg.extraCompatPackages or [ ]
  );

  # MangoHud config file for mangoapp
  mangoConfigFile = pkgs.writeText "mangohud.conf" cfg.mangoConfig;

  # State is stored in user's XDG_RUNTIME_DIR (secure, per-user, kernel-enforced isolation)

  # Find next available TTY (starting from 7, skipping occupied ones)
  findAvailableTty = pkgs.writeShellScript "find-available-tty" ''
    for tty in $(${lib.getExe' pkgs.coreutils "seq"} 7 12); do
      # Check if TTY is in use via fuser
      if ! ${lib.getExe' pkgs.procps "fuser"} "/dev/tty$tty" >/dev/null 2>&1; then
        echo "$tty"
        exit 0
      fi
    done
    # Fallback to tty7
    echo "7"
  '';

  # Get current VT number via sysfs (works without /dev/tty access)
  getCurrentVt = pkgs.writeShellScript "get-current-vt" ''
    vt=$(${lib.getExe' pkgs.coreutils "cat"} /sys/class/tty/tty0/active 2>/dev/null)
    # Extract number, validate it's numeric
    vt_num=$(echo "$vt" | ${lib.getExe' pkgs.gnused "sed"} 's/tty//' | ${lib.getExe' pkgs.gnused "sed"} 's/[^0-9]//g')
    if [[ -n "$vt_num" ]]; then
      echo "$vt_num"
    else
      echo "1"
    fi
  '';

  # Save session state before switching to gamemode (runs as user)
  saveSessionState = pkgs.writeShellScript "save-session-state" ''
    # Check if gamescope session is already running
    if ${lib.getExe' pkgs.systemd "systemctl"} is-active --quiet gamescope-session.service; then
      echo "Error: Gamescope session is already running" >&2
      exit 1
    fi

    STATE_DIR="$XDG_RUNTIME_DIR/gamescope-session"
    ${lib.getExe' pkgs.coreutils "mkdir"} -p "$STATE_DIR"

    # Save original TTY (use sysfs, works without /dev/tty access)
    ${getCurrentVt} > "$STATE_DIR/original-tty"

    # Find and save target TTY for gamescope
    target_tty=$(${findAvailableTty})
    echo "$target_tty" > "$STATE_DIR/target-tty"

    # Save display environment for steam restart
    echo "''${DISPLAY:-}" > "$STATE_DIR/display"
    echo "''${WAYLAND_DISPLAY:-}" > "$STATE_DIR/wayland-display"
    echo "''${DBUS_SESSION_BUS_ADDRESS:-}" > "$STATE_DIR/dbus-address"

    # Check if steam is running and save state
    if ${lib.getExe' pkgs.procps "pgrep"} -x steam >/dev/null 2>&1; then
      echo "1" > "$STATE_DIR/steam-was-running"
      # Shutdown steam gracefully
      ${lib.getExe cfg.steamPackage} -shutdown || true
      # Wait for steam to exit (max 15 seconds)
      for i in $(${lib.getExe' pkgs.coreutils "seq"} 1 30); do
        ${lib.getExe' pkgs.procps "pgrep"} -x steam >/dev/null 2>&1 || break
        ${lib.getExe' pkgs.coreutils "sleep"} 0.5
      done
    else
      echo "0" > "$STATE_DIR/steam-was-running"
    fi
  '';

  # HDR reset script (shared between modes)
  resetHdr = pkgs.writeShellScript "reset-hdr" ''
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
  '';

  # Patch for wlserver lock race condition (upstream PR #2023)
  # Fixes: Assertion 'wlserver_is_lock_held()' failed on second session start
  wlserverLockPatch = pkgs.fetchurl {
    url = "https://github.com/ValveSoftware/gamescope/pull/2023.patch";
    hash = "sha256-I6CDtlEBOALo0FqsJDW2jjHxkla/GrBw8vlyUQ4zEdU=";
  };

  patchGamescope =
    pkg:
    pkg.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ wlserverLockPatch ];
    });

  defaultGamescopePackage = patchGamescope (
    if config.foundrix.hardware.gpu.usesUnstablePackages or false then
      pkgsUnstable.gamescope
    else
      pkgs.gamescope
  );

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
    ${lib.optionalString (
      extraCompatPaths != ""
    ) ''export STEAM_EXTRA_COMPAT_TOOLS_PATHS="${extraCompatPaths}"''}

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

    # Save PID for recovery service to use
    echo "$gamescope_pid" > "$XDG_RUNTIME_DIR/gamescope-session/gamescope.pid"

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
    # Security: only allow users to start sessions as themselves
    if [[ "$user" != "$SUDO_USER" ]]; then
      echo "Error: Can only start gamescope session as yourself" >&2
      exit 1
    fi
    if ${lib.getExe' pkgs.coreutils "id"} "$user" &>/dev/null; then
      echo "$user" > /run/gamescope-session-user
    else
      echo "Invalid user: $user" >&2
      exit 1
    fi
  '';

  # greetd config format
  greetdFormat = pkgs.formats.toml { };

  # Template config - VT and user are substituted at runtime
  greetdConfigTemplate = greetdFormat.generate "greetd-template.toml" {
    terminal.vt = 0; # placeholder, replaced at runtime
    initial_session = {
      command = "${gamescope-session-run}";
      user = "PLACEHOLDER_USER"; # replaced at runtime
    };
    default_session = {
      command = "${gamescope-session-run}";
      user = "PLACEHOLDER_USER"; # replaced at runtime
    };
  };

  # Generate greetd config at runtime with actual TTY and user
  gamescope-greetd-config = pkgs.writeShellScript "gamescope-greetd-config" ''
    GSUSER=$(${lib.getExe' pkgs.coreutils "cat"} /run/gamescope-session-user)
    GSUID=$(${lib.getExe' pkgs.coreutils "id"} -u "$GSUSER")
    STATE_DIR="/run/user/$GSUID/gamescope-session"
    TARGET_TTY=$(${lib.getExe' pkgs.coreutils "cat"} "$STATE_DIR/target-tty" 2>/dev/null || echo "7")
    # Validate TTY is numeric
    TARGET_TTY=$(echo "$TARGET_TTY" | ${lib.getExe' pkgs.gnused "sed"} 's/[^0-9]//g')
    [[ -z "$TARGET_TTY" ]] && TARGET_TTY=7
    ${lib.getExe' pkgs.gnused "sed"} \
      -e "s/vt = 0/vt = $TARGET_TTY/" \
      -e "s/PLACEHOLDER_USER/$GSUSER/g" \
      ${greetdConfigTemplate} > /run/gamescope-greetd.toml
  '';

  # Wrapper that generates config and runs greetd
  gamescope-session-wrapper = pkgs.writeShellScript "gamescope-session-wrapper" ''
    set -euo pipefail
    ${gamescope-greetd-config}
    GSUSER=$(${lib.getExe' pkgs.coreutils "cat"} /run/gamescope-session-user)
    GSUID=$(${lib.getExe' pkgs.coreutils "id"} -u "$GSUSER")
    STATE_DIR="/run/user/$GSUID/gamescope-session"
    TARGET_TTY=$(${lib.getExe' pkgs.coreutils "cat"} "$STATE_DIR/target-tty" 2>/dev/null || echo "7")
    # Validate TTY is numeric
    TARGET_TTY=$(echo "$TARGET_TTY" | ${lib.getExe' pkgs.gnused "sed"} 's/[^0-9]//g')
    [[ -z "$TARGET_TTY" ]] && TARGET_TTY=7
    ${lib.getExe' pkgs.kbd "chvt"} "$TARGET_TTY"
    exec ${lib.getExe pkgs.greetd} --config /run/gamescope-greetd.toml
  '';

  # Implementation scripts for session switching (run via user services to survive DM stop)
  gamescope-switch-impl = pkgs.writeShellScriptBin "gamescope-switch-impl" ''
    set -euo pipefail
    # Save current state (TTY, steam running, find target TTY) - runs as user
    ${saveSessionState}
    /run/wrappers/bin/sudo ${write-gamescope-user} "$USER"
    ${lib.optionalString cfg.restartDisplayManager ''
      ${lib.getExe' pkgs.systemd "systemctl"} stop display-manager.service
    ''}
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
  imports = [
    foundrixModules.components.steam
  ];

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
      description = ''
        Gamescope package to use.
        The default package includes a patch for the wlserver lock race condition
        (upstream PR #2023) that fixes assertion failures on session restart.
      '';
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

    restartDisplayManager = lib.mkOption {
      type = lib.types.bool;
      description = ''
        Whether to stop/restart display-manager when switching sessions.
        When false (default): gamescope runs on a separate TTY alongside your desktop.
        When true: display-manager is stopped when entering game mode and restarted on exit.
      '';
      default = false;
    };

    desktopEntry = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = gamemode-desktop-entry;
      description = ''
        The desktop entry package for switching to game mode.
        Read-only. Can be referenced in other modules.

        Examples:

        Add to system packages:
          environment.systemPackages = [ config.foundrix.config.gamescope-session.desktopEntry ];

        GNOME favorites (via Home Manager dconf):
          dconf.settings."org/gnome/shell".favorite-apps = [
            "gamescope-session.desktop"
            # ... other apps
          ];

        KDE Plasma taskbar (via plasma-manager panels):
          programs.plasma.panels = [{
            widgets = [{
              iconTasks.launchers = [
                "applications:gamescope-session.desktop"
                # ... other apps
              ];
            }];
          }];

        Get the .desktop file path:
          "''${config.foundrix.config.gamescope-session.desktopEntry}/share/applications/gamescope-session.desktop"
      '';
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
      # Only conflict with display-manager if we're stopping/restarting it
      conflicts = lib.mkIf cfg.restartDisplayManager [ "display-manager.service" ];
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
        # greetd handles TTY allocation dynamically based on state file
        StandardOutput = "journal";
        StandardError = "journal";
        # Clean up temp files on stop (normal or failed)
        ExecStopPost = "${lib.getExe' pkgs.coreutils "rm"} -f /run/gamescope-session-user /run/gamescope-greetd.toml";
      };
    };

    # Recovery service to return to desktop
    systemd.services.gamescope-session-recovery = {
      description = "Return from Gamescope session to desktop";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "gamescope-session-recover" ''
          ${lib.getExe' pkgs.systemd "systemctl"} stop gamescope-session.service || true

          # Get user info and state directory
          SESSION_USER=$(${lib.getExe' pkgs.coreutils "cat"} /run/gamescope-session-user 2>/dev/null || echo "")
          if [[ -n "$SESSION_USER" ]]; then
            uid=$(${lib.getExe' pkgs.coreutils "id"} -u "$SESSION_USER")
            STATE_DIR="/run/user/$uid/gamescope-session"
          else
            STATE_DIR=""
          fi

          # Kill only our gamescope instance using saved PID
          if [[ -n "$STATE_DIR" ]] && [[ -f "$STATE_DIR/gamescope.pid" ]]; then
            GAMESCOPE_PID=$(${lib.getExe' pkgs.coreutils "cat"} "$STATE_DIR/gamescope.pid")
            if [[ -n "$GAMESCOPE_PID" ]] && ${lib.getExe' pkgs.coreutils "kill"} -0 "$GAMESCOPE_PID" 2>/dev/null; then
              ${lib.getExe' pkgs.coreutils "kill"} -9 "$GAMESCOPE_PID" 2>/dev/null || true
            fi
          else
            # Fallback: kill all gamescope (shouldn't happen normally)
            ${lib.getExe' pkgs.procps "pkill"} -9 gamescope || true
          fi

          # Reset HDR state on monitors
          ${resetHdr}

          # Read saved state
          if [[ -n "$STATE_DIR" ]]; then
            ORIGINAL_TTY=$(${lib.getExe' pkgs.coreutils "cat"} "$STATE_DIR/original-tty" 2>/dev/null || echo "1")
            STEAM_WAS_RUNNING=$(${lib.getExe' pkgs.coreutils "cat"} "$STATE_DIR/steam-was-running" 2>/dev/null || echo "0")
            SAVED_DISPLAY=$(${lib.getExe' pkgs.coreutils "cat"} "$STATE_DIR/display" 2>/dev/null || echo "")
            SAVED_WAYLAND=$(${lib.getExe' pkgs.coreutils "cat"} "$STATE_DIR/wayland-display" 2>/dev/null || echo "")
            SAVED_DBUS=$(${lib.getExe' pkgs.coreutils "cat"} "$STATE_DIR/dbus-address" 2>/dev/null || echo "")
          else
            ORIGINAL_TTY="1"
            STEAM_WAS_RUNNING="0"
          fi

          # Validate TTY is numeric
          ORIGINAL_TTY=$(echo "$ORIGINAL_TTY" | ${lib.getExe' pkgs.gnused "sed"} 's/[^0-9]//g')
          [[ -z "$ORIGINAL_TTY" ]] && ORIGINAL_TTY=1

          ${
            if cfg.restartDisplayManager then
              ''
                # restartDisplayManager mode: restart display-manager
                ${lib.getExe' pkgs.kbd "chvt"} 1
                ${lib.getExe' pkgs.systemd "systemctl"} restart display-manager.service
              ''
            else
              ''
                # Default mode: switch back to original TTY
                ${lib.getExe' pkgs.kbd "chvt"} "$ORIGINAL_TTY"

                # Restart Steam if it was running before switching to gamemode
                if [[ "$STEAM_WAS_RUNNING" == "1" ]] && [[ -n "$SESSION_USER" ]]; then
                  export XDG_RUNTIME_DIR="/run/user/$uid"
                  # Use saved display environment
                  ${lib.getExe' pkgs.systemd "runuser"} -u "$SESSION_USER" -- \
                    env DISPLAY="$SAVED_DISPLAY" \
                        WAYLAND_DISPLAY="$SAVED_WAYLAND" \
                        DBUS_SESSION_BUS_ADDRESS="$SAVED_DBUS" \
                    ${lib.getExe' pkgs.systemd "systemd-run"} --user --scope \
                    ${lib.getExe cfg.steamPackage} &
                fi
              ''
          }

          # Clean up state files
          if [[ -n "$STATE_DIR" ]]; then
            ${lib.getExe' pkgs.coreutils "rm"} -rf "$STATE_DIR"
          fi
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
        dmServices = lib.filter (
          name: lib.elem "display-manager.service" (config.systemd.services.${name}.aliases or [ ])
        ) (lib.attrNames config.systemd.services);
        # Build list: gamescope-session + display-manager + all actual DM services + recovery
        allowedUnits = [
          "gamescope-session"
          "gamescope-session-recovery"
          "display-manager"
        ]
        ++ dmServices;
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
    foundrix.components.steam.gamescope.enable = true;
    programs.gamescope = {
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

    security.pam.services.greetd = {
      allowNullPassword = true;
      startSession = true;
    };

    # This is set by gamescopeSession in nixpkgs, so set it here, too
    security.wrappers.bwrap = lib.mkIf cfg.realtimeScheduling {
      owner = "root";
      group = "root";
      source = lib.getExe' pkgs.bubblewrap "bwrap";
      setuid = true;
    };
  };
}

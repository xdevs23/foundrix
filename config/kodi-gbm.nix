{
  lib,
  pkgsUnstable,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    user = lib.mkOption {
      type = lib.types.str;
      description = "Which user to set up Kodi for";
    };
    plugins = lib.mkOption {
      type = with lib.types; anything;
      description = "Plugins to install (see kodiPackages). Lambda.";
      default = (kodiPkgs: [ ]);
    };
    kodiData = lib.mkOption {
      type = lib.types.str;
      default = "/home/${(namespacedCfg __curPos).user}/.kodi";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      kodiPackage = pkgsUnstable.kodi-gbm.withPackages cfg.plugins;
    in
    lib.mkMerge [
      {
        systemd.services.kodi = {
          description = "Kodi";

          wantedBy = [ "multi-user.target" ];
          after = [
            "sound.target"
            "systemd-user-sessions.service"
          ];

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = cfg.user;
            Environment = [
              "LIRC_SOCKET_PATH=/run/lirc/lircd"
              "KODI_DATA=${cfg.kodiData}"
            ];
            ExecStart = "${kodiPackage}/bin/kodi --standalone --audio-backend=alsa";
            Restart = "always";
            TimeoutStopSec = "15s";
            TimeoutStopFailureMode = "kill";
          };
        };
        environment.systemPackages = with pkgsUnstable; [
          kodiPackage
          # Important codec packages
          libde265
          libavif
          libaom
          bento4
          # GStreamer
          gst_all_1.gstreamer
          gst_all_1.gst-plugins-base
          gst_all_1.gst-plugins-good
          gst_all_1.gst-plugins-bad
          gst_all_1.gst-plugins-ugly
          gst_all_1.gst-libav
          gst_all_1.gst-vaapi
          # Make sure we have everything else
          ldacbt
          libfreeaptx
          faad2
          tagparser
          x265
          libdovi
          lame
          libogg
          flac
          libvorbis
          libcdio
          libmodplug
          libsamplerate
          openal
          sbc
          wavpack
          speexdsp
          speex
          soxr
          libheif
          lcms
          libraw
          libpng
          libjpeg
          libtiff
          exiv2
          harfbuzz
          spirv-headers
          spirv-tools
          spirv-llvm-translator
          vulkan-tools
          jasper
          jellyfin-ffmpeg
          libaacs
          libass
          libdvdcss
          libdvdnav
          libdvdread
          libudfread
          libva
          libvdpau
          rtmpdump
          zvbi
          nghttp2
          libmicrohttpd
          alsa-utils
        ];
        fonts.fontDir.enable = true;
        services.libinput.enable = true;
        services.xserver.displayManager.lightdm.greeter.enable = false;
        services.displayManager.autoLogin.user = cfg.user;
        # We want to have ALSA as sound system. Kodi will play well with this
        # and it allows us to do HDMI passthrough.
        hardware.alsa.enable = true;
        hardware.alsa.enablePersistence = false;
        hardware.bluetooth.enable = true;
        hardware.bluetooth.powerOnBoot = true;
        hardware.graphics.enable = true;
        services.pipewire.enable = false;
        services.pipewire.socketActivation = false;
        xdg.icons.enable = true;
      }
      {
        users.users.${cfg.user} = {
          extraGroups = [
            "video"
            "input"
            "audio"
          ];
        };
      }
    ];
}

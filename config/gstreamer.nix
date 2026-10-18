{ pkgs, lib, ... }:
{
  environment.systemPackages =
    with pkgs.gst_all_1;
    [
      gstreamer
      gst-plugins-base
      gst-plugins-good
      gst-plugins-bad
      gst-plugins-ugly
      gst-libav
    ]
    # GStreamer 1.28 removed gst-vaapi. The va plugin, which ships in
    # gst-plugins-bad, replaces it.
    ++ lib.optional (!lib.versionAtLeast lib.version "26.10") gst-vaapi;
}

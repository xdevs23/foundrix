{ pkgs, lib, ... }:
{
  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      noto-fonts-cjk-sans
      liberation_ttf
    ];
    fontconfig = {
      enable = lib.mkDefault true;
      defaultFonts = {
        serif = lib.mkDefault [ "Liberation Serif" ];
        sansSerif = lib.mkDefault [ "Liberation Sans" ];
        monospace = lib.mkDefault [ "Liberation Mono" ];
        emoji = lib.mkDefault [ "Noto Color Emoji" ];
      };
      hinting = {
        enable = lib.mkDefault true;
        style = lib.mkDefault "slight";
      };
      subpixel.rgba = lib.mkDefault "rgb";
    };
  };
}

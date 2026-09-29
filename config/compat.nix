{ pkgs, ... }:
{
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    alsa-lib
    libGL
    libICE
    libSM
    libX11
    libXcursor
    libXext
    libXi
    libXinerama
    libXrandr
    libpulseaudio
    libxkbcommon
    wayland

    libgcc
    gcc
  ];
}

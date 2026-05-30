{ pkgs, lib, ... }:
let
  xorgPkgs = if lib.versionAtLeast lib.version "26.04" then pkgs else pkgs.xorg;
in
{
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    alsa-lib
    libGL
    xorgPkgs.libICE
    xorgPkgs.libSM
    xorgPkgs.libX11
    xorgPkgs.libXcursor
    xorgPkgs.libXext
    xorgPkgs.libXi
    xorgPkgs.libXinerama
    xorgPkgs.libXrandr
    libpulseaudio
    libxkbcommon
    wayland

    libgcc
    gcc
  ];
}

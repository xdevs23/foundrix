{ lib, ... }:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableBashIntegration = lib.mkDefault true;
    enableZshIntegration = lib.mkDefault true;
  };
}

{
  lib,
  config,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    buildDirOnTmp = lib.mkEnableOption "storing build directories on /nix/tmp (requires foundrix.config.filesystem.nix-tmp)";
  };
  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      nix = {
        enable = lib.mkForce true;
        gc = {
          automatic = true;
          dates = lib.mkDefault "weekly";
          options = lib.mkDefault "--delete-older-than 60d";
        };
        settings = {
          max-jobs = lib.mkDefault 4;
          cores = lib.mkDefault (config.device.cpu.threads or 1);
          build-dir = lib.mkIf cfg.buildDirOnTmp "/nix/tmp";
          experimental-features = [
            "nix-command"
            "flakes"
          ];
        };
        extraOptions = ''
          min-free = ${toString (4096 * 1024 * 1024)}
          max-free = ${toString (8192 * 1024 * 1024)}
        '';
      };
    };
}

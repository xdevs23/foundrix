{ lib, ... }:
{
  nixpkgs.overlays = [
    (
      final: prev:
      let
        checkDisable = (
          old: {
            doCheck = false;
            doInstallCheck = false;
          }
        );
      in
      lib.optionalAttrs (!prev.stdenv.hostPlatform.isx86_64) {
        swtpm = prev.swtpm.overrideAttrs checkDisable;
        tpm2-tss = prev.tpm2-tss.overrideAttrs checkDisable;
        polkit = prev.polkit.overrideAttrs checkDisable;
        umockdev = prev.umockdev.overrideAttrs checkDisable;
      }
    )
  ];
}

{ lib, ... }:
let
  overlays = [
    (
      final: prev:
      let
        checkDisable = (
          final: prev: {
            doCheck = false;
            doInstallCheck = false;
          }
        );
      in
      (lib.optionalAttrs (!prev.stdenv.hostPlatform.isx86_64) {
        polkit = prev.polkit.overrideAttrs checkDisable;
        umockdev = prev.umockdev.overrideAttrs checkDisable;
        swtpm = prev.swtpm.overrideAttrs checkDisable;
        tpm2-tss = prev.tpm2-tss.overrideAttrs checkDisable;
      })
    )
  ];
in
{
  nixpkgs.overlays = overlays;
  nixpkgs-unstable.overlays = overlays;
}

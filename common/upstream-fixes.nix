{ ... }:
{
  nixpkgs.overlays = [
    # Cross-compilation fixes
    (final: prev: {
      /*iniparser = prev.iniparser.overrideAttrs (old: {
        doCheck = final.stdenv.buildPlatform.canExecute final.stdenv.hostPlatform;
      });*/
    })
  ];
}

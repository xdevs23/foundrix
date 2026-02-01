{ pkgsUnstable, ... }:
{
  cachyos-x86_64_v3 =
    (pkgsUnstable.proton-ge-bin.overrideAttrs (
      prev: final: {
        # chore: update from https://github.com/CachyOS/proton-cachyos/releases
        src = pkgsUnstable.fetchzip {
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20260127-slr/proton-cachyos-10.0-20260127-slr-x86_64_v3.tar.xz";
          hash = "sha512-AOE5RctR/Y93WutlNxoWADc/z3bEQFSTZG8isV21E58mTKZ+L9eL2ErLtVkUFT/7SMJVyA3Rqy8AHn4GJsp7fw==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20260127-slr-x86_64_v3";
      }
    )).override
      { steamDisplayName = "Proton-CachyOS x86_64_v3"; };
  cachyos-x86_64_v4 =
    (pkgsUnstable.proton-ge-bin.overrideAttrs (
      prev: final: {
        # chore: update from https://github.com/CachyOS/proton-cachyos/releases
        src = pkgsUnstable.fetchzip {
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20260127-slr/proton-cachyos-10.0-20260127-slr-x86_64_v4.tar.xz";
          hash = "sha512-EcPs/sp6Y5p9VUi933iwwPqLO2NjXkKlHwZtCVcN2QXQMeNT85b/YafJly9Oe8M1XsSo0FiMdiDynI2Uo/RWGw==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20260127-slr-x86_64_v4";
      }
    )).override
      { steamDisplayName = "Proton-CachyOS x86_64_v4"; };
}

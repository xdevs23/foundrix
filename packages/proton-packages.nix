{ pkgsUnstable, ... }:
{
  cachyos-x86_64_v3 =
    (pkgsUnstable.proton-ge-bin.overrideAttrs (
      prev: final: {
        # chore: update from https://github.com/CachyOS/proton-cachyos/releases
        src = pkgsUnstable.fetchzip {
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20251222-slr/proton-cachyos-10.0-20251222-slr-x86_64_v3.tar.xz";
          hash = "sha512-O03PrU0i3A6ghXtXaRGq3DDeNbWXxMhF8BXB3hgt/2OaCsELLcA6mLywgy2vttywwhBCbKO8P4HBdkWycwTUsQ==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20251222-slr-x86_64_v3";
      }
    )).override
      { steamDisplayName = "Proton-CachyOS x86_64_v3"; };
  cachyos-x86_64_v4 =
    (pkgsUnstable.proton-ge-bin.overrideAttrs (
      prev: final: {
        # chore: update from https://github.com/CachyOS/proton-cachyos/releases
        src = pkgsUnstable.fetchzip {
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20251222-slr/proton-cachyos-10.0-20251222-slr-x86_64_v4.tar.xz";
          hash = "sha512-bK6G7kbPJCQIYIPbKYSqDTMlM1rwGk9wOm6ZPR3TZ1lXv7sQOgSOtLRaSCCGo8GUFu3azT15j+G98WY6Zr1F8A==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20251222-slr-x86_64_v4";
      }
    )).override
      { steamDisplayName = "Proton-CachyOS x86_64_v4"; };
}

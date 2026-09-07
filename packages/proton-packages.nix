{ pkgsUnstable, ... }:
{
  cachyos-x86_64_v3 =
    (pkgsUnstable.proton-ge-bin.overrideAttrs (
      prev: final: {
        # chore: update from https://github.com/CachyOS/proton-cachyos/releases
        # gh api repos/CachyOS/proton-cachyos/releases/latest --jq '.tag_name, (.assets[] | select(.name | test("x86_64_v[34]")) | .browser_download_url)'
        # nix-prefetch-url --unpack --type sha512 <url> | nix hash convert --hash-algo sha512 --to sri
        src = pkgsUnstable.fetchzip {
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-11.0-20260703-slr/proton-cachyos-11.0-20260703-slr-x86_64_v3.tar.xz";
          hash = "sha512-8mBCMXiUNcunVe6aVhGgpxRSRxJc9ijDuZe3IWfINaNrZjybGMOHK3QhzlOXWsnt+xbewP69kLh2D8cjNA8Eig==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-11.0-20260703-slr-x86_64_v3";
        steamDisplayName = "Proton-CachyOS x86_64_v3";
      }
    ));
}

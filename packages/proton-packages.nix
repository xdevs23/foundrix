{ pkgsUnstable, ... }:
{
  cachyos-x86_64_v3 =
    (pkgsUnstable.proton-ge-bin.overrideAttrs (
      prev: final: {
        # chore: update from https://github.com/CachyOS/proton-cachyos/releases
        # gh api repos/CachyOS/proton-cachyos/releases/latest --jq '.tag_name, (.assets[] | select(.name | test("x86_64_v[34]")) | .browser_download_url)'
        # nix-prefetch-url --unpack --type sha512 <url> | nix hash convert --hash-algo sha512 --to sri
        src = pkgsUnstable.fetchzip {
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20260207-slr/proton-cachyos-10.0-20260207-slr-x86_64_v3.tar.xz";
          hash = "sha512-YGbQsLfFQ7Gz91/KihkWbBPfVmizyCvISOTPz0WZ/zsd58M5pur27xTF8/Cz8sQzlOTRVVo0tEVDyx2pim2Uwg==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20260207-slr-x86_64_v3";
      }
    )).override
      { steamDisplayName = "Proton-CachyOS x86_64_v3"; };
  cachyos-x86_64_v4 =
    (pkgsUnstable.proton-ge-bin.overrideAttrs (
      prev: final: {
        # chore: update from https://github.com/CachyOS/proton-cachyos/releases
        # gh api repos/CachyOS/proton-cachyos/releases/latest --jq '.tag_name, (.assets[] | select(.name | test("x86_64_v[34]")) | .browser_download_url)'
        # nix-prefetch-url --unpack --type sha512 <url> | nix hash convert --hash-algo sha512 --to sri
        src = pkgsUnstable.fetchzip {
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20260207-slr/proton-cachyos-10.0-20260207-slr-x86_64_v4.tar.xz";
          hash = "sha512-JDhWe+dXPiu1tQ/i9D60Dc6T3nguAOc/lozg9iVZ0mgjCVhzyzr7QiLe8law0WXXNoRB2FawUABQn51VhsDN1A==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20260207-slr-x86_64_v4";
      }
    )).override
      { steamDisplayName = "Proton-CachyOS x86_64_v4"; };
}

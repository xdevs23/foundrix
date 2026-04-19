{ pkgsUnstable, ... }:
{
  cachyos-x86_64_v3 =
    (pkgsUnstable.proton-ge-bin.overrideAttrs (
      prev: final: {
        # chore: update from https://github.com/CachyOS/proton-cachyos/releases
        # gh api repos/CachyOS/proton-cachyos/releases/latest --jq '.tag_name, (.assets[] | select(.name | test("x86_64_v[34]")) | .browser_download_url)'
        # nix-prefetch-url --unpack --type sha512 <url> | nix hash convert --hash-algo sha512 --to sri
        src = pkgsUnstable.fetchzip {
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20260409-slr/proton-cachyos-10.0-20260409-slr-x86_64_v3.tar.xz";
          hash = "sha512-QKVtl+4+oyYH01iBzeUDfAdGxHrcO8aIP+L2tQcqY37QpcjkJgcUujmrTlHsq34Tqj/UfdQfYmaI9JQ8PE6KaA==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20260409-slr-x86_64_v3";
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
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20260409-slr/proton-cachyos-10.0-20260409-slr-x86_64_v4.tar.xz";
          hash = "sha512-5UcE31VEyEw6srhvoCgDuJUhSQU0x4CNLG+/OaOO7lIsjvaBVs9g4oam5mQfWv8O833JZd93LBwRTmKcfz2WyA==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20260409-slr-x86_64_v4";
      }
    )).override
      { steamDisplayName = "Proton-CachyOS x86_64_v4"; };
}

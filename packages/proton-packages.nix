{ pkgsUnstable, ... }:
{
  cachyos-x86_64_v3 =
    (pkgsUnstable.proton-ge-bin.overrideAttrs (
      prev: final: {
        # chore: update from https://github.com/CachyOS/proton-cachyos/releases
        # gh api repos/CachyOS/proton-cachyos/releases/latest --jq '.tag_name, (.assets[] | select(.name | test("x86_64_v[34]")) | .browser_download_url)'
        # nix-prefetch-url --unpack --type sha512 <url> | nix hash convert --hash-algo sha512 --to sri
        src = pkgsUnstable.fetchzip {
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20260320-slr/proton-cachyos-10.0-20260320-slr-x86_64_v3.tar.xz";
          hash = "sha512-vISCW1s4YBQmfF7J6IUQmR2QXHKQ+Xa7a7tfX4Rx0hyL93TpUkR5u8nlXshCzeOqFsqPGcKA4rvOGNJCt2rswQ==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20260320-slr-x86_64_v3";
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
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20260320-slr/proton-cachyos-10.0-20260320-slr-x86_64_v4.tar.xz";
          hash = "sha512-9QUP9GkMpAg2/g6kXDmaJoECbPBYL1Ok08bgYLUqE1Ql2jwiG/o9UIH/fJcAqtjT3Ywc//9w+UOXis7NtkKOPg==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20260320-slr-x86_64_v4";
      }
    )).override
      { steamDisplayName = "Proton-CachyOS x86_64_v4"; };
}

{ pkgsUnstable, ... }:
{
  cachyos-x86_64_v3 =
    (pkgsUnstable.proton-ge-bin.overrideAttrs (
      prev: final: {
        # chore: update from https://github.com/CachyOS/proton-cachyos/releases
        # gh api repos/CachyOS/proton-cachyos/releases/latest --jq '.tag_name, (.assets[] | select(.name | test("x86_64_v[34]")) | .browser_download_url)'
        # nix-prefetch-url --unpack --type sha512 <url> | nix hash convert --hash-algo sha512 --to sri
        src = pkgsUnstable.fetchzip {
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20260228-slr/proton-cachyos-10.0-20260228-slr-x86_64_v3.tar.xz";
          hash = "sha512-BudWfuKzU/1B1GiZ3iDaRgXEzjFtJm4wrW2EVLM5BcWEJeh9OQnsTkpIEJ6tG15EpIUM35+XQ+2yjMDSbkbkag==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20260228-slr-x86_64_v3";
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
          url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-10.0-20260228-slr/proton-cachyos-10.0-20260228-slr-x86_64_v4.tar.xz";
          hash = "sha512-FNE3RliuwrCevw7Neg8I2tNQtIxl+HP5vsD3MytX2LLuWOPnOJnLy9IKsW0M81l1V3VhhK6XbnZIEsEEdee+kQ==";
        };
        pname = "proton-cachyos";
        version = "proton-cachyos-10.0-20260228-slr-x86_64_v4";
      }
    )).override
      { steamDisplayName = "Proton-CachyOS x86_64_v4"; };
}

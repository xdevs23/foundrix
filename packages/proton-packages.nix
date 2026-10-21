{ pkgsUnstable, ... }:
{
  cachyos-x86_64_v3 = pkgsUnstable.proton-ge-bin.overrideAttrs (
    final: prev: {
      # chore: update from https://github.com/CachyOS/proton-cachyos/releases
      # gh api repos/CachyOS/proton-cachyos/releases/latest --jq '.tag_name, (.assets[] | select(.name | test("x86_64_v[34]")) | .browser_download_url)'
      # nix-prefetch-url --unpack --type sha512 <url> | nix hash convert --hash-algo sha512 --to sri
      src = pkgsUnstable.fetchzip {
        url = "https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-11.0-20261015-slr/proton-cachyos-11.0-20261015-slr-x86_64_v3.tar.xz";
        hash = "sha512-N4+OC4edI6mH0WVXE/NNwP0qT6Pz06f+y6kipTMSF0yfEUaXUDK49VaIUpSEK0/JDOy7CVbig6VBsADjrHGPtA==";
      };
      pname = "proton-cachyos";
      version = "proton-cachyos-11.0-20261015-slr-x86_64_v3";
      # Must match the tool's internal name in the tarball's compatibilitytool.vdf
      # (upstream's preFixup replaces it with steamDisplayName).
      toolName = final.version;
      steamDisplayName = "Proton-CachyOS x86_64_v3";
    }
  );
}

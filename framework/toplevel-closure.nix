{ pkgs, config, ... }:
let
  closureInfo = pkgs.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };
in
{
  config.system.build.closureInfo = closureInfo;

  # Pre-built merged store directory (not used by QEMU launcher, kept for other consumers)
  config.system.build.toplevelClosure = pkgs.runCommandLocal "nix-store" { } ''
    mkdir -p $out
    echo "Constructing nix store from toplevel closure"
    while IFS= read -r path; do
      cp --reflink=auto -a "$path" $out/
    done < ${closureInfo}/store-paths
  '';
}

{ pkgs, config, ... }:
let
  closureInfo = pkgs.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };
in
{
  # Create a merged directory with all closure paths
  config.system.build.toplevelClosure = pkgs.runCommandLocal "nix-store" { } ''
    mkdir -p $out
    echo "Constructing nix store from toplevel closure"
    while IFS= read -r path; do
      cp --reflink=auto -a "$path" $out/
    done < ${closureInfo}/store-paths
    echo "Copying to the nix store"
  '';
}

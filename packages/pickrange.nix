{ pkgs, ... }:
pkgs.symlinkJoin {
  pname = "pickrange";
  version = "0.1.0";
  paths = [
    (pkgs.writeShellScriptBin "pickrange" ''
      git rev-list --reverse --topo-order $1^..$2 | while read rev
      do echo "$rev"; done | xargs git cherry-pick -s
    '')
    (pkgs.writeShellScriptBin "pickrangeib" ''
      git rev-list --reverse --topo-order $1^..$2 | while read rev
      do git cherry-pick -s $rev || git cherry-pick --skip; done
    '')
  ];
}

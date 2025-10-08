{ pkgs, ... }:
pkgs.symlinkJoin {
  name = "git-aliases";
  paths = [
    (pkgs.writeShellScriptBin "gpick" ''
      exec git cherry-pick -s "$@"
    '')
  ];
}

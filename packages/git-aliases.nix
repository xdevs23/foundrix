{ pkgs, ... }:
pkgs.symlinkJoin {
  pname = "git-aliases";
  version = "0.1.0";
  paths = [
    (pkgs.writeShellScriptBin "gpick" ''
      exec git cherry-pick -s "$@"
    '')
  ];
}

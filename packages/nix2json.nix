{ pkgs, lib, ... }:
pkgs.writeShellScriptBin "nix2json" ''
  ${lib.getExe pkgs.nix} eval --arg-from-stdin stdin --expr "{ stdin }: { output = builtins.toJSON (import (builtins.toFile \"stdin\" stdin)); }" --raw output
''

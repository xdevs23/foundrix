{ pkgs, lib, ... }:
pkgs.writeShellScriptBin "json2nix" ''
  ${lib.getExe pkgs.nix} eval --arg-from-stdin stdin --expr "{ stdin }: { output = builtins.fromJSON stdin; }" output | \
    ${lib.getExe pkgs.nixfmt-rfc-style}
''

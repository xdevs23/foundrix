{ callPackage }:
let
  src = builtins.fetchTree {
    type = "github";
    owner = "xdevs23";
    repo = "rockflasher";
    # chore: update rockflasher revision to latest commit
    # git ls-remote https://github.com/xdevs23/rockflasher.git HEAD
    # nix flake prefetch github:xdevs23/rockflasher/<rev> --json | jq -r .hash
    rev = "6f13b171e599c286b37d251ff39eda808b91abda";
    narHash = "sha256-/rLfeuK0w7CmX4/o3wRSp5+Av4LBJBR+Xb5bv5uNQ0U=";
  };
in
callPackage "${src}/package.nix" { }

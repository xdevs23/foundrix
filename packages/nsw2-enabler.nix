{ pkgs, ... }:
let
  src = pkgs.fetchFromGitHub {
    owner = "ikz87";
    repo = "NSW2-controller-enabler";
    # chore: update nsw2-enabler revision
    # git ls-remote https://github.com/ikz87/NSW2-controller-enabler.git HEAD
    # nix-prefetch-url --unpack https://github.com/ikz87/NSW2-controller-enabler/archive/<rev>.tar.gz \
    #   | nix hash convert --hash-algo sha256 --to sri
    rev = "cb8946f34f7befab35860ce9f45155cf3edc68ff";
    hash = "sha256-4IjNzlPOCHTWzQ63jrHpb89Qwq07VHxSFDSFsYiKvzg=";
  };
in
pkgs.writers.writePython3Bin "nsw2-enable-hid"
  {
    libraries = with pkgs.python3Packages; [
      pyusb
      hid
      python-uinput
    ];
    flakeIgnore = [
      "E226"
      "E261"
      "E265"
      "E302"
      "E305"
      "E501"
      "F401"
      "W391"
    ];
  }
  (builtins.readFile "${src}/enable_hid.py")

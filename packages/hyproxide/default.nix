{
  lib,
  rustPlatform,
  callPackage,
  clippy,
  rustfmt,
}:
let
  cargoCheck = import ../../lib/cargo-check.nix;
  hyprlandCheck = callPackage ../../lib/hyprland-check.nix { };
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "hyproxide";
  version = "0.1.0";

  # The crate and its test fixtures, the crate hyproxide-testing.
  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  passthru.tests = {
    # `--all-targets` leaves out the live tests, whose manifest entries set
    # `test = false`.
    clippy = cargoCheck finalAttrs.finalPackage "clippy" clippy ''
      cargo clippy --frozen --workspace --all-targets -- -D warnings
      cargo clippy --frozen --test live --test live_events -- -D warnings
    '';
    fmt = cargoCheck finalAttrs.finalPackage "fmt" rustfmt "cargo fmt --all --check";

    live = hyprlandCheck {
      name = "hyproxide-live";
      package = finalAttrs.finalPackage;
      targets = [
        "live"
        "live_events"
      ];
    };
  };

  meta = {
    description = "Client for the IPC sockets of Hyprland 0.57 and later";
    homepage = "https://github.com/simao/foundrix";
    license = lib.licenses.gpl3Only;
  };
})

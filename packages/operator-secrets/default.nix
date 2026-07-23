{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "operator-secrets";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Boot-blocking daemon + TUI collecting operator-provided secrets";
    mainProgram = "operator-secretsd";
  };
}

{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "var-disk-manager";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Initrd daemon + TUI managing the encrypted /var data volume";
    mainProgram = "var-disk-managerd";
  };
}

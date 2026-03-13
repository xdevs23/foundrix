{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "flasher-tui";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "TUI for selecting a target disk and flashing a system image";
    license = lib.licenses.gpl3Only;
    mainProgram = "flasher-tui";
  };
}

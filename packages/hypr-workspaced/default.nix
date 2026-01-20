{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "hypr-workspaced";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Daemon for managing synchronized virtual workspaces across multiple Hyprland monitors";
    homepage = "https://github.com/simao/foundrix";
    license = lib.licenses.gpl3Only;
    mainProgram = "hypr-workspaced";
  };
}

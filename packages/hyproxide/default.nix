{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "hyproxide";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Client for the IPC sockets of Hyprland 0.57 and later";
    homepage = "https://github.com/simao/foundrix";
    license = lib.licenses.gpl3Only;
  };
}

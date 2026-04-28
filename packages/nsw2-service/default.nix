{
  lib,
  rustPlatform,
  pkg-config,
  libusb1,
}:
rustPlatform.buildRustPackage {
  pname = "nsw2-service";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libusb1 ];

  meta = {
    description = "Linux userspace driver for Nintendo Switch 2 controllers";
    license = lib.licenses.gpl3Only;
    mainProgram = "nsw2-service";
  };
}

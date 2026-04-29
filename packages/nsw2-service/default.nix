{
  lib,
  rustPlatform,
  pkg-config,
  libusb1,
  hidapi,
  udev,
}:
rustPlatform.buildRustPackage {
  pname = "nsw2-service";
  version = "0.2.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    libusb1
    hidapi
    udev
  ];

  meta = {
    description = "Linux userspace driver for Nintendo Switch 2 controllers";
    license = lib.licenses.gpl3Only;
    mainProgram = "nsw2-service";
  };
}

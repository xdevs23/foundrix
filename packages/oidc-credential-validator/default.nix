{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "oidc-credential-validator";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "operator-secrets validator proving OIDC client credentials by a real token request";
    mainProgram = "oidc-credential-validator";
  };
}

{
  lib,
  rustPlatform,
  clippy,
  rustfmt,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "hyproxide";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  passthru.tests =
    let
      # A build of the crate with its vendored dependencies that runs one
      # cargo command in place of building, testing and installing.
      cargoCheck =
        name: tool: command:
        finalAttrs.finalPackage.overrideAttrs (previous: {
          pname = "hyproxide-${name}";
          nativeBuildInputs = previous.nativeBuildInputs ++ [ tool ];
          buildPhase = ''
            runHook preBuild
            ${command}
            runHook postBuild
          '';
          doCheck = false;
          installPhase = "touch $out";
        });
    in
    {
      clippy = cargoCheck "clippy" clippy "cargo clippy --frozen --all-targets -- -D warnings";
      fmt = cargoCheck "fmt" rustfmt "cargo fmt --check";
    };

  meta = {
    description = "Client for the IPC sockets of Hyprland 0.57 and later";
    homepage = "https://github.com/simao/foundrix";
    license = lib.licenses.gpl3Only;
  };
})

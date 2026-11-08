{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "hypr-workspaced";
  version = "0.1.0";

  # The crate and hyproxide, its path dependency.
  src = lib.fileset.toSource {
    root = ./..;
    fileset = lib.fileset.unions [
      ./.
      ../hyproxide
    ];
  };
  sourceRoot = "${finalAttrs.src.name}/hypr-workspaced";

  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Daemon for managing synchronized virtual workspaces across multiple Hyprland monitors";
    homepage = "https://github.com/simao/foundrix";
    license = lib.licenses.gpl3Only;
    mainProgram = "hypr-workspaced";
  };
})

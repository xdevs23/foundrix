{
  lib,
  rustPlatform,
  clippy,
  rustfmt,
  jq,
  testers,
  hyprland,
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

      # The test binary of tests/live.rs, at $out/bin/hyproxide-live. Cargo
      # adds a hash to its file name and reports that name as JSON.
      liveTests = finalAttrs.finalPackage.overrideAttrs (previous: {
        pname = "hyproxide-live-tests";
        nativeBuildInputs = previous.nativeBuildInputs ++ [ jq ];
        buildPhase = ''
          runHook preBuild
          cargo test --frozen --test live --no-run --message-format=json \
            | jq --raw-output 'select(.reason == "compiler-artifact" and .target.name == "live") | .executable' \
            > live-executable
          runHook postBuild
        '';
        doCheck = false;
        installPhase = ''install -D "$(cat live-executable)" $out/bin/hyproxide-live'';
      });
    in
    {
      # `--all-targets` leaves out tests/live.rs, whose manifest entry sets
      # `test = false`.
      clippy = cargoCheck "clippy" clippy ''
        cargo clippy --frozen --all-targets -- -D warnings
        cargo clippy --frozen --test live -- -D warnings
      '';
      fmt = cargoCheck "fmt" rustfmt "cargo fmt --check";

      live = testers.runNixOSTest {
        name = "hyproxide-live";
        nodes.machine = {
          # vkms is the only display device: Hyprland takes it over.
          boot.kernelModules = [ "vkms" ];
          virtualisation.qemu.options = [ "-vga none" ];
          hardware.graphics.enable = true;
          # The seat for Hyprland. With the builtin backend of libseat, each
          # Hyprland forks a seat server that hangs when it exits.
          services.seatd.enable = true;
          environment.systemPackages = [ hyprland ];
        };
        # `systemctl start` returns once seatd is ready, and runs without the
        # time limit of `wait_for_unit`.
        testScript = ''
          print(machine.succeed(
              "systemctl start seatd.service"
              " && LIBSEAT_BACKEND=seatd ${liveTests}/bin/hyproxide-live --test-threads=1"
          ))
        '';
      };
    };

  meta = {
    description = "Client for the IPC sockets of Hyprland 0.57 and later";
    homepage = "https://github.com/simao/foundrix";
    license = lib.licenses.gpl3Only;
  };
})

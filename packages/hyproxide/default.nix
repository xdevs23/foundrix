{
  lib,
  rustPlatform,
  clippy,
  rustfmt,
  jq,
  testers,
  hyprland,
  foot,
  dejavu_fonts,
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

      # The test binaries of tests/live.rs and tests/live_events.rs, at
      # $out/bin/<target>. Cargo adds a hash to their file names and reports
      # those names as JSON.
      liveTests = finalAttrs.finalPackage.overrideAttrs (previous: {
        pname = "hyproxide-live-tests";
        nativeBuildInputs = previous.nativeBuildInputs ++ [ jq ];
        buildPhase = ''
          runHook preBuild
          cargo test --frozen --test live --test live_events --no-run --message-format=json \
            | jq --raw-output 'select(.reason == "compiler-artifact" and .executable != null) | "\(.target.name) \(.executable)"' \
            > live-executables
          runHook postBuild
        '';
        doCheck = false;
        installPhase = ''
          while read -r target executable; do
            install -D "$executable" "$out/bin/$target"
          done < live-executables
        '';
      });
    in
    {
      # `--all-targets` leaves out the live tests, whose manifest entries set
      # `test = false`.
      clippy = cargoCheck "clippy" clippy ''
        cargo clippy --frozen --all-targets -- -D warnings
        cargo clippy --frozen --test live --test live_events -- -D warnings
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
          # foot is the window the event test opens, and needs a font.
          environment.systemPackages = [
            hyprland
            foot
          ];
          fonts.packages = [ dejavu_fonts ];
        };
        # `systemctl start` returns once seatd is ready, and runs without the
        # time limit of `wait_for_unit`. With `--nocapture`, what a test writes
        # to stderr reaches the log as it happens, also when the test hangs.
        testScript = ''
          machine.succeed("systemctl start seatd.service")
          for target in ["live", "live_events"]:
              print(machine.succeed(
                  f"LIBSEAT_BACKEND=seatd ${liveTests}/bin/{target} --test-threads=1 --nocapture"
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

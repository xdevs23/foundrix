# A NixOS VM check that runs test targets of a Rust package against headless
# Hyprlands, which the tests start with the crate hyproxide-testing.
# `machine` and `setup` add to the machine and to the test script before the
# tests, and `environment` sets variables for them.
{
  lib,
  jq,
  testers,
  hyprland,
  foot,
  dejavu_fonts,
}:
{
  name,
  package,
  targets,
  machine ? { },
  setup ? "",
  environment ? { },
}:
let
  # The test binaries of the targets, at $out/bin/<target>. Cargo adds a
  # hash to their file names and reports those names as JSON.
  executables = package.overrideAttrs (previous: {
    pname = "${previous.pname}-hyprland-tests";
    nativeBuildInputs = previous.nativeBuildInputs ++ [ jq ];
    buildPhase = ''
      runHook preBuild
      cargo test --frozen ${
        lib.concatMapStringsSep " " (target: "--test ${target}") targets
      } --no-run --message-format=json \
        | jq --raw-output 'select(.reason == "compiler-artifact" and .executable != null) | "\(.target.name) \(.executable)"' \
        > hyprland-test-executables
      runHook postBuild
    '';
    doCheck = false;
    installPhase = ''
      while read -r target executable; do
        install -D "$executable" "$out/bin/$target"
      done < hyprland-test-executables
    '';
  });
  variables = lib.concatStringsSep " " (
    lib.mapAttrsToList (variable: value: "${variable}=${lib.escapeShellArg value}") environment
  );
in
testers.runNixOSTest {
  inherit name;
  nodes.machine = {
    imports = [ machine ];
    # vkms is the only display device: Hyprland takes it over.
    boot.kernelModules = [ "vkms" ];
    virtualisation.qemu.options = [ "-vga none" ];
    hardware.graphics.enable = true;
    # The seat for Hyprland. With the builtin backend of libseat, each
    # Hyprland forks a seat server that hangs when it exits.
    services.seatd.enable = true;
    # foot is the window tests open, and needs a font.
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
    ${setup}
    for target in ${builtins.toJSON targets}:
        print(machine.succeed(
            f"LIBSEAT_BACKEND=seatd ${variables} ${executables}/bin/{target} --test-threads=1 --nocapture"
        ))
  '';
}

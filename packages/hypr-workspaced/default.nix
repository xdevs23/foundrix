{
  lib,
  callPackage,
  rustPlatform,
  clippy,
  rustfmt,
}:
let
  cargoCheck = import ../../lib/cargo-check.nix;
  hyprlandCheck = callPackage ../../lib/hyprland-check.nix { };
in
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

  passthru.tests =
    let
      # The user service the end-to-end test names to the daemon in place of
      # the top bar.
      restartedService = "top-bar-stand-in.service";
    in
    {
      # `--all-targets` leaves out the end-to-end test, whose manifest entry
      # sets `test = false`.
      clippy = cargoCheck finalAttrs.finalPackage "clippy" clippy ''
        cargo clippy --frozen --all-targets -- -D warnings
        cargo clippy --frozen --test end_to_end -- -D warnings
      '';
      fmt = cargoCheck finalAttrs.finalPackage "fmt" rustfmt "cargo fmt --check";

      end-to-end = hyprlandCheck {
        name = "hypr-workspaced-end-to-end";
        package = finalAttrs.finalPackage;
        targets = [ "end_to_end" ];
        machine =
          { pkgs, ... }:
          {
            environment.systemPackages = [ finalAttrs.finalPackage ];
            systemd.user.services.${lib.removeSuffix ".service" restartedService} = {
              description = "Stand-in for the top bar that hypr-workspaced restarts";
              serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
            };
          };
        # The user manager of root, whose session bus the daemon and the test
        # use.
        setup = ''
          machine.succeed("systemctl start user@0.service")
        '';
        environment = {
          DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/0/bus";
          RESTARTED_SERVICE = restartedService;
        };
      };
    };

  meta = {
    description = "Daemon for managing synchronized virtual workspaces across multiple Hyprland monitors";
    homepage = "https://github.com/simao/foundrix";
    license = lib.licenses.gpl3Only;
    mainProgram = "hypr-workspaced";
  };
})

{ ... }@args:
let
  customLib = {
    images = import ./images.nix (args // { inherit customLib; });
    qemu-launch = import ./qemu-launch.nix (args // { inherit customLib; });
  };
in
customLib

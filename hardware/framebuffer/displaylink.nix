{
  pkgsUnstable,
  config,
  modulesPath,
  extendKernelPackages,
  ...
}:
let
  # chore: update from https://github.com/DisplayLink/evdi/releases
  # gh api repos/DisplayLink/evdi/releases/latest --jq .tag_name
  # nix store prefetch-file --unpack --json https://github.com/DisplayLink/evdi/archive/refs/tags/v<TAG>.tar.gz | jq -r .hash
  evdiVersion = "1.15.1";
  evdiSrc = pkgsUnstable.fetchFromGitHub {
    owner = "DisplayLink";
    repo = "evdi";
    tag = "v${evdiVersion}";
    hash = "sha256-3g6OETXJSf6AScJ2K9F67mPlh3Wpi20Yq+f+xe78p9Y=";
  };
  evdiFor =
    kernel:
    (pkgsUnstable.linuxPackagesFor kernel).evdi.overrideAttrs {
      version = evdiVersion;
      src = evdiSrc;
    };
in
{
  imports = [
    "${modulesPath}/hardware/video/displaylink.nix"
  ];
  environment.systemPackages = [ pkgsUnstable.displaylink ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ evdi ];
  services.xserver.videoDrivers = [
    "displaylink"
    "modesetting"
  ];
  # The upstream module hardcodes boot.kernelPackages.evdi with no package
  # option, so the pinned driver has to replace it inside the kernel package
  # set.
  nixpkgs.overlays = [
    (extendKernelPackages (kernel: {
      evdi = evdiFor kernel;
    }))
  ];
}

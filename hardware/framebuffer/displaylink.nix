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
  # evdi's conftest probes compile without KBUILD_MODNAME. On kernels built
  # with CONFIG_MEM_ALLOC_PROFILING every allocator expands through alloc
  # tags that need it, so the kzalloc_obj probe fails and evdi's fallback
  # macro shadows the kernel's own one. Drop once upstream merges the fix:
  # https://github.com/DisplayLink/evdi/pull/592
  evdiConftestPatch = pkgsUnstable.fetchpatch {
    url = "https://github.com/DisplayLink/evdi/commit/18e709424a67e6daf191e683cd2a14dd032b4196.patch";
    hash = "sha256-6kxeN/xN0msWmxGg8SnTCBOsPn1a6UOJwSJVeKjGSu8=";
  };
  evdiFor =
    kernel:
    (pkgsUnstable.linuxPackagesFor kernel).evdi.overrideAttrs (
      _final: prev: {
        version = evdiVersion;
        src = evdiSrc;
        patches = (prev.patches or [ ]) ++ [ evdiConftestPatch ];
        # 1.15.0 no longer includes /etc/os-release from module/Makefile,
        # which is the only thing the nixpkgs prePatch rewrites.
        prePatch = "";
      }
    );
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

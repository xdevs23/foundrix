{
  config,
  pkgsUnstable,
  mkConfigurableUsersOption,
  namespaced,
  namespacedCfg,
  usersOrAll,
  ...
}:
{
  options = namespaced __curPos {
    users = mkConfigurableUsersOption {
      description = "Which users to apply razer configuration to. Defaults to all users.";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
      kernel = config.boot.kernelPackages.kernel;
      # chore: update from https://github.com/openrazer/openrazer/releases
      # gh api repos/openrazer/openrazer/releases/latest --jq .tag_name
      # nix store prefetch-file --unpack --json https://github.com/openrazer/openrazer/archive/refs/tags/v<TAG>.tar.gz | jq -r .hash
      openrazerVersion = "3.12.4";
      openrazerSrc = pkgsUnstable.fetchFromGitHub {
        owner = "openrazer";
        repo = "openrazer";
        tag = "v${openrazerVersion}";
        hash = "sha256-WgDYs0ehnzWlX/wvfur0UhFLbZv7jZ6FMybqDaFDuLg=";
      };
    in
    {
      hardware.openrazer.enable = true;
      hardware.openrazer.users = usersOrAll cfg.users;
      # boot.kernelPackages (e.g. linuxPackages_latest) is assembled inside
      # nixpkgs' linuxKernel set, so an overlay on the top-level
      # linuxPackagesFor alias never reaches it. Build the module from the
      # unstable driver expression against the configured kernel and hand it
      # to the NixOS module directly.
      hardware.openrazer.packages.kernel =
        (pkgsUnstable.linuxPackagesFor kernel).openrazer.overrideAttrs
          {
            version = "${openrazerVersion}-${kernel.version}";
            src = openrazerSrc;
          };
      environment.systemPackages = with pkgsUnstable; [
        openrazer-daemon
        polychromatic
      ];
    };
}

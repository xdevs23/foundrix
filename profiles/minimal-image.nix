{ modulesPath, foundrixModules, lib, ... }:
{
  imports = with foundrixModules; [
    "${modulesPath}/profiles/image-based-appliance.nix"
    "${modulesPath}/profiles/perlless.nix"
    config.filesystem.root-tmpfs
    framework.disk-image
  ];
  boot.initrd.systemd.enable = true;
  boot.loader.timeout = 0;
  system.forbiddenDependenciesRegexes = lib.mkForce [ ];
  system.stateVersion = lib.mkDefault (builtins.substring 0 5 lib.version);
}

{ modulesPath, foundrixModules, ... }:
{
  imports = with foundrixModules; [
    "${modulesPath}/profiles/image-based-appliance.nix"
    "${modulesPath}/profiles/perlless.nix"
    config.filesystem.root-tmpfs
  ];
  boot.initrd.systemd.enable = true;
}

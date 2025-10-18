{ modulesPath, foundrixModules, ... }:
{
  imports = with foundrixModules; [
    "${modulesPath}/profiles/image-based-appliance.nix"
    "${modulesPath}/profiles/perlless.nix"
    config.filesystem.root-tmpfs
    framework.ota
  ];
  boot.initrd.systemd.enable = true;
  foundrix.framework.ota.updateServer = "http://127.0.0.1";
}

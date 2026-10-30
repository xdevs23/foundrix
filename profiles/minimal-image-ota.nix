{
  modulesPath,
  foundrixModules,
  lib,
  ...
}:
{
  imports = with foundrixModules; [
    "${modulesPath}/profiles/image-based-appliance.nix"
    "${modulesPath}/profiles/perlless.nix"
    config.filesystem.root-tmpfs
    framework.repart-disk-image
    framework.ota
  ];
  boot.initrd.systemd.enable = lib.mkIf (!lib.versionAtLeast lib.version "26.10") true;
  foundrix.framework.ota.updateServer = "http://127.0.0.1";
  system.stateVersion = lib.mkDefault (builtins.substring 0 5 lib.version);
}

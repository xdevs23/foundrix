{
  foundrixModules,
  foundrix,
  lib,
  ...
}:
{
  imports = with foundrixModules; [
    config.security.pam-login-limits
    config.appimage
    config.compat
    config.mdraid
    config.networking.network-discovery
    config.oomd
    config.repart-config
    config.filesystem.esp
    config.filesystem.root-tmpfs
    config.media.pipewire
    profiles.all-packages
    framework.disk-image
    framework.uefi-secure-boot
  ];
  networking.hostName = builtins.head (
    lib.strings.splitString "." (builtins.baseNameOf __curPos.file)
  );
  boot.loader.systemd-boot = {
    enable = lib.mkDefault true;
    configurationLimit = lib.mkDefault 5;
    consoleMode = lib.mkDefault "max";
  };
  boot.initrd.systemd.enable = true;
  foundrix.framework.uefi-secure-boot.keys = {
    includeWindows = true;
    includeMSUEFI = true;
    includeMSOptionROM = true;
    includeLegacyWindows = true;
    includeLegacyMSUEFI = true;
  };
  system.build.curPos = __curPos;
  system.build.foundrixPath = "${foundrix}";
  system.stateVersion = lib.mkDefault (builtins.substring 0 5 lib.version);
}

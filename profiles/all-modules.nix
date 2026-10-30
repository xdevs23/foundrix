{
  foundrixModules,
  foundrix,
  lib,
  ...
}:
{
  imports = with foundrixModules; [
    config.linux.sysrq
    config.graphics.cursors.breezex-rosepine
    config.media.pipewire
    config.networking.network-discovery
    config.security.all-strong
    config.shell.zsh.lite
    config.virtualisation.docker
    config.appimage
    config.basic-fonts
    config.basic-user-system
    config.clamav
    config.compat
    config.gstreamer
    config.home-jdk
    config.home-manager
    config.mdraid
    config.nix
    config.oomd
    config.repart-config
    config.virtd
    config.vscode-opinionated
    profiles.all-packages
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
  boot.initrd.systemd.enable = lib.mkIf (!lib.versionAtLeast lib.version "26.10") true;
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

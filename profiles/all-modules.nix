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
    config.oomd
    config.repart-config
    config.filesystem.esp
    config.filesystem.root-tmpfs
  ];
  networking.hostName = builtins.head (
    lib.strings.splitString "." (builtins.baseNameOf __curPos.file)
  );
  boot.loader.systemd-boot = {
    enable = lib.mkDefault true;
    configurationLimit = lib.mkDefault 5;
    consoleMode = lib.mkDefault "max";
  };
  system.build.curPos = __curPos;
  system.build.foundrixPath = "${foundrix}";
}

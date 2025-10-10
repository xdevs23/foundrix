{
  foundrixModules,
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
  ];
  networking.hostName = builtins.head (
    lib.strings.splitString "." (builtins.baseNameOf __curPos.file)
  );
}

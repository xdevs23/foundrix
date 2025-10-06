{
  foundrixModules,
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
}

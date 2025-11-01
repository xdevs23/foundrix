{ foundrixModules, ... }:
{
  imports = with foundrixModules.config.security; [
    linux-fs
    linux-kernel
    network
    pam-login-limits
    userspace
  ];
}

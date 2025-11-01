{ foundrixModules, ... }:
{
  imports = with foundrixModules.config.security; [
    all
    linux-kernel-strong
    network-strong
    userspace-strong
  ];
}

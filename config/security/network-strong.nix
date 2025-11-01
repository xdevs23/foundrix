# Enables strong network security. This may affect usability of
# certain applications like games. Some anti-cheat engines will
# refuse to start games if this is enabled.
{ foundrixModules, ... }:
{
  imports = [
    foundrixModules.config.security.network
  ];

  boot.kernel.sysctl = {
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;
    "net.core.bpf_jit_harden" = 2;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.tcp_syn_retries" = 2;
    "net.ipv4.tcp_synack_retries" = 2;
    "net.ipv4.tcp_max_syn_backlog" = 4096;
    "net.ipv4.tcp_rfc1337" = 1;
    "net.ipv4.conf.all.log_martians" = true;
    "net.ipv4.conf.default.log_martians" = true;
  };
}

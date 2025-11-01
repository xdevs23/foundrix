{
  networking.nftables.enable = true;
  networking.firewall.enable = true;
  networking.firewall.trustedInterfaces = [ "lo" ];
}

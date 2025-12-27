{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  services.rpcbind.enable = true;

  # Disable mDNS in resolved (avahi handles it)
  services.resolved.extraConfig = "MulticastDNS=no";
}

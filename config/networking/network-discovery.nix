{ lib, ... }:
{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  services.rpcbind.enable = true;

  # Disable mDNS in resolved (avahi handles it)
  services.resolved =
    if lib.versionAtLeast lib.version "26.05" then
      { settings.Resolve.MulticastDNS = "no"; }
    else
      { extraConfig = "MulticastDNS=no"; };
}

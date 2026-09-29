{ lib, ... }:
{
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
  services.rpcbind.enable = true;

  # The avahi module sets ConfigurationDirectory=avahi/services only to
  # guarantee /etc/avahi/services exists (the real config comes from a
  # store path via -f). systemd creates that directory at service start,
  # which fails before exec on an immutable /etc overlay
  # (status=241/CONFIGURATION_DIRECTORY). Provide the directory
  # declaratively instead, which works on read-only and mutable /etc
  # alike.
  systemd.services.avahi-daemon.serviceConfig.ConfigurationDirectory = lib.mkForce "";
  environment.etc."avahi/services/.keep".text = "";

  # Disable mDNS in resolved (avahi handles it)
  services.resolved.settings.Resolve.MulticastDNS = "no";
}

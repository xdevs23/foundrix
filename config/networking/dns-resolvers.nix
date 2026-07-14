{
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;
in
{
  options = namespaced __curPos {
    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "1.1.1.1"
        "2606:4700:4700::1111"
      ];
      description = "Primary DNS servers";
    };

    fallbackDns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "1.1.1.1"
        "1.0.0.1"
        "2606:4700:4700::1111"
        "2606:4700:4700::1001"
        "9.9.9.9"
        "2620:fe::fe"
      ];
      description = "Fallback DNS servers for systemd-resolved";
    };
  };

  config = {
    networking.nameservers = cfg.nameservers;

    services.resolved = {
      enable = true;
      settings.Resolve.FallbackDNS = cfg.fallbackDns;
    };
  };
}

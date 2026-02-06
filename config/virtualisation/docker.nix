{
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    rootless.enable = lib.mkEnableOption "rootless docker";
    autostart = lib.mkEnableOption "docker starting at boot";
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      virtualisation.docker.enable = true;
      virtualisation.docker.rootless = lib.optionalAttrs cfg.rootless.enable {
        enable = true;
        setSocketVariable = true;
      };
      virtualisation.docker.storageDriver = "overlay2";
      systemd.services.docker = lib.mkIf (!cfg.autostart) {
        wantedBy = lib.mkForce [ ];
        serviceConfig = {
          Restart = lib.mkForce "no";
        };
      };
      virtualisation.docker.daemon.settings = {
        userland-proxy = true;
        ipv6 = true;
        fixed-cidr-v6 = "fd00::/80";
      };
      virtualisation.containers.enable = true;
      environment.sessionVariables.COMPOSE_BAKE = "false";
    };
}

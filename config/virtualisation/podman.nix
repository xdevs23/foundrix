{
  lib,
  namespaced,
  namespacedCfg,
  pkgs,
  ...
}:
{
  options = namespaced __curPos {
    autostart = lib.mkEnableOption "podman starting at boot";
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      virtualisation = {
        containers.enable = true;
        podman = {
          enable = true;
          defaultNetwork.settings.dns_enabled = true;
        };
      };
      systemd.services.podman.wantedBy = lib.mkIf (!cfg.autostart) (lib.mkForce [ ]);
      environment.systemPackages = [
        pkgs.podman-compose
      ];
    };
}

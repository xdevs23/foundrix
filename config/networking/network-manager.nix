{
  lib,
  config,
  foundrixModules,
  traitTypes,
  ...
}:
let
  rootType = config.foundrix.traits.filesystem.rootType or null;
  isVolatileRoot = rootType == traitTypes.filesystem.rootType.volatile;
in
{
  imports = [
    foundrixModules.framework.traits.filesystem
  ];

  options = { };

  config = lib.mkMerge [
    {
      networking.networkmanager.enable = true;
      networking.useDHCP = lib.mkDefault true;
      systemd.services.NetworkManager-wait-online.enable = lib.mkDefault false;
    }

    (lib.mkIf isVolatileRoot {
      environment.etc."NetworkManager".source = "/var/etc/NetworkManager";

      systemd.tmpfiles.settings."var-etc-nm"."/var/etc/NetworkManager".d = {
        mode = "0755";
        user = "0";
        group = "0";
      };
    })
  ];
}

{ mkConfigurableUsersOption, namespaced, namespacedCfg, ... }:
{
  options = namespaced __curPos {
    users = mkConfigurableUsersOption {
      description = "Users to add to the cdrom group";
    };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      users.groups.cdrom.members = cfg.users;
      boot.kernelModules = [ "sg" ];
    };
}

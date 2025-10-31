{
  mkConfigurableUsersOption,
  namespaced,
  namespacedCfg,
  usersOrAll,
  ...
}:
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
      users.groups.cdrom.members = usersOrAll cfg.users;
      boot.kernelModules = [ "sg" ];
    };
}

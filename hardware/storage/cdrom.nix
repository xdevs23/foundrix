{ config, mkConfigurableUsersOption, ... }:
{
  options = {
    foundrix.hardware.storage.cdrom.users = mkConfigurableUsersOption {
      description = "Users to add to the cdrom group";
    };
  };

  config = {
    users.groups.cdrom.members = config.foundrix.hardware.storage.cdrom.users;
    boot.kernelModules = [ "sg" ];
  };
}

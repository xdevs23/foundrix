{
  pkgs,
  mkConfigurableUsersOption,
  usersOrAll,
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    users = mkConfigurableUsersOption {
      description = "Which users to apply virtd support to. Defaults to all users.";
    };
  };

  config = {
    users.groups.libvirtd.members = usersOrAll (namespacedCfg __curPos).users;
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        # From 25.11, OVMF is distributed with qemu by default
        ovmf = lib.mkIf (lib.versionOlder lib.version "25.10") {
          enable = true;
          packages = [
            (pkgs.OVMF.override {
              secureBoot = true;
              tpmSupport = true;
            }).fd
          ];
        };
      };
    };
  };
}

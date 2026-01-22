{
  pkgs,
  mkConfigurableUsersOption,
  applyHomeManagerUsers,
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
      package = pkgs.libvirt.override {
        enableXen = lib.warnIf (!pkgs.stdenv.buildPlatform.isx86 && pkgs.stdenv.hostPlatform.isx86_64) ''
          cross-compilation of libvirtd with xen for x86_64 on non-x86 is not supported due to syslinux incompatibility.
          Disabling enableXen of pkgs.libvirt.
        '' (pkgs.stdenv.buildPlatform.isx86 && pkgs.stdenv.hostPlatform.isx86_64);
      };
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
      };
    };
    home-manager = applyHomeManagerUsers (namespacedCfg __curPos).users {
      home.sessionVariables = {
        LIBVIRT_DEFAULT_URI = "qemu:///system";
      };
    };
  };
}

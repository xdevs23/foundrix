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
        enableXen = lib.warnIf (!pkgs.buildPlatform.isx86 && pkgs.hostPlatform.isx86_64) ''
          cross-compilation of libvirtd with xen for x86_64 on non-x86 is not supported due to syslinux incompatibility.
          Disabling enableXen of pkgs.libvirt.
        '' (pkgs.buildPlatform.isx86 && pkgs.hostPlatform.isx86_64);
      };
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
    home-manager = applyHomeManagerUsers (namespacedCfg __curPos).users {
      home.sessionVariables = {
        LIBVIRT_DEFAULT_URI = "qemu:///system";
      };
    };
  };
}

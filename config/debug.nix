{ ... }:
{
  users.allowNoPasswordLogin = true;
  boot.initrd.systemd = {
    emergencyAccess = true;
  };
  boot.kernelParams = [
    "systemd.setenv=SYSTEMD_SULOGIN_FORCE=1"
    "systemd.log_level=debug"
    "systemd.crash_action=emergency"
  ];
  security.pam.services.login.rootOK = true;
}

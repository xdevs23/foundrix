{
  lib,
  pkgs,
  ...
}:
{
  # Allow passwordless login for live environment
  users.allowNoPasswordLogin = true;

  # Emergency/debug access
  boot.initrd.systemd = {
    emergencyAccess = true;
    users.root.shell = pkgs.runtimeShell;
  };

  # Disable network by default - live images often run offline
  systemd.network.wait-online.enable = false;
  systemd.network.enable = lib.mkOverride 60 false;
  networking.useDHCP = false;

  # Basic utilities expected in a live environment
  environment.systemPackages = with pkgs; [
    coreutils
    util-linux
  ];
}

{
  pkgs,
  lib,
  ...
}:
{
  services.dbus.enable = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    lsof
    file
  ];
  boot = {
    kernelPackages = lib.mkOverride 101 pkgs.linuxPackages_latest;
    tmp.useTmpfs = lib.mkDefault true;
    loader.systemd-boot = {
      enable = lib.mkDefault true;
      configurationLimit = lib.mkDefault 5;
      consoleMode = lib.mkDefault "max";
    };
  };

}

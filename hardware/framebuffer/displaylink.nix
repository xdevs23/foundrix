{
  pkgs,
  config,
  modulesPath,
  ...
}:
{
  imports = [
    "${modulesPath}/hardware/video/displaylink.nix"
  ];
  environment.systemPackages = [ pkgs.unstable.displaylink ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ evdi ];
  services.xserver.videoDrivers = [
    "displaylink"
    "modesetting"
  ];
}

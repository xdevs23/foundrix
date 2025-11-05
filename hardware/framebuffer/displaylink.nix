{
  pkgsUnstable,
  config,
  modulesPath,
  ...
}:
{
  imports = [
    "${modulesPath}/hardware/video/displaylink.nix"
  ];
  environment.systemPackages = [ pkgsUnstable.displaylink ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ evdi ];
  services.xserver.videoDrivers = [
    "displaylink"
    "modesetting"
  ];
}

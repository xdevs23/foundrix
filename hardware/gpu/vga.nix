{
  lib,
  pkgs,
  namespaced,
  ...
}:
{

  options = namespaced __curPos {
    isSupported = lib.mkOption {
      type = lib.types.bool;
      default = true;
      readOnly = true;
      description = "Whether generic VGA hardware is supported";
    };
  };

  config = {
    environment.systemPackages =
      with pkgs; [
        opencl-headers
        clinfo
        vulkan-tools
      ];
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
  };
}

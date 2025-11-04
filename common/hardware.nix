{
  lib,
  config,
  ...
}:
{
  options = {
    foundrix.hardware = {
      gpu.usesUnstablePackages = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
        description = "Whether foundrix is aware that unstable GPU packages are being used";
        default =
          (
            (config.foundrix.hardware.gpu.amd.isSupported or false)
            && (config.foundrix.hardware.gpu.amd.useUnstablePackages or false)
          )
          || (
            (config.foundrix.hardware.gpu.intel.isSupported or false)
            && (config.foundrix.hardware.gpu.intel.useUnstablePackages or false)
          );
      };
    };
  };
}

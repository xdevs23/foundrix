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
          with config.foundrix.hardware.gpu.amd;
          (isSupported && useUnstablePackages)
          || (with config.foundrix.hardware.gpu.intel; (isSupported && useUnstablePackages));
      };
    };
  };
}

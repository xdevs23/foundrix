{
  pkgs,
  lib,
  config,
  ...
}:
let
  amdGpuSupport = config.foundrix.hardware.gpu.amd.isSupported or false;
  intelGpuSupport = config.foundrix.hardware.gpu.intel.isSupported or false;
  rocmPackages = config.foundrix.hardware.gpu.amd.rocmPackages or [ ];

  ollamaPackage =
    if intelGpuSupport then
      pkgs.unstable.ollama
    else if amdGpuSupport then
      pkgs.unstable.ollama-rocm.override { inherit rocmPackages; }
    else
      pkgs.unstable.ollama;

  rocmScript = config.foundrix.hardware.gpu.amd.rocmScript;
in
{
  environment.systemPackages = [
    ollamaPackage
  ]
  ++ (lib.optionals amdGpuSupport [
    (rocmScript "ollama-rocm" ''
      export OLLAMA_NUM_GPU_LAYERS=9999
      exec ${lib.getExe ollamaPackage} "$@"
    '')
  ])
  ++ (lib.optionals intelGpuSupport [
    (pkgs.writeShellScriptBin "ollama-intel" ''
      #!${pkgs.runtimeShell}
      export OLLAMA_INTEL_GPU=1
      export SYCL_DEVICE_FILTER=level_zero:gpu
      export ZES_ENABLE_SYSMAN=1
      export SYCL_PI_LEVEL_ZERO_USE_IMMEDIATE_COMMANDLISTS=1
      exec ${lib.getExe ollamaPackage} "$@"
    '')
  ]);
}

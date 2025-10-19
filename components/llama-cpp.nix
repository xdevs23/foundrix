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

  llamaPackage =
    if intelGpuSupport then
      pkgs.unstable.llama-cpp-vulkan
    else if amdGpuSupport then
      pkgs.unstable.llama-cpp.override {
        inherit rocmPackages;
        rocmSupport = true;
      }
    else
      pkgs.unstable.llama-cpp;

  rocmScript = config.foundrix.hardware.gpu.amd.rocmScript;
in
{
  environment.systemPackages = [
    llamaPackage
  ]
  ++ (lib.optionals amdGpuSupport [
    (rocmScript "llama-rocm" ''
      exec ${lib.getExe' llamaPackage "llama-cli"} -ngl 99 "$@"
    '')
    (rocmScript "llama-rocm-server" ''
      exec ${lib.getExe' llamaPackage "llama-server"} -ngl 99 "$@"
    '')
  ])
  ++ (lib.optionals intelGpuSupport [
    (pkgs.writeShellScriptBin "llama-intel" ''
      exec ${lib.getExe' llamaPackage "llama-cli"} -ngl 99 "$@"
    '')
    (pkgs.writeShellScriptBin "llama-intel" ''
      exec ${lib.getExe' llamaPackage "llama-server"} -ngl 99 "$@"
    '')
  ])
  ++ [
    (pkgs.writeShellScriptBin "llama-vulkan" ''
      exec ${lib.getExe' llamaPackage "llama-cli"} -ngl 99 "$@"
    '')
    (pkgs.writeShellScriptBin "llama-vulkan" ''
      exec ${lib.getExe' llamaPackage "llama-server"} -ngl 99 "$@"
    '')
  ];
}

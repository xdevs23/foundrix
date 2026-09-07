{
  config,
  lib,
  pkgsUnstable,
  extendKernelPackages,
  ...
}:
{
  # ryzen_smu only exists for x86_64; the guard keeps the module inert on
  # other platforms so profiles that import every module still evaluate.
  config = lib.mkIf config.nixpkgs.hostPlatform.isx86_64 {
    hardware.cpu.amd.ryzen-smu.enable = true;
    # The upstream module hardcodes boot.kernelPackages.ryzen-smu with no
    # package option. The unstable driver expression tracks kernel API
    # changes faster than the stable one, so build it against whichever
    # kernel the system selects.
    nixpkgs.overlays = [
      (extendKernelPackages (kernel: {
        ryzen-smu = (pkgsUnstable.linuxPackagesFor kernel).ryzen-smu;
      }))
    ];
  };
}

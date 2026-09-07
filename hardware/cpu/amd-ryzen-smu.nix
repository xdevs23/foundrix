{
  config,
  lib,
  pkgsUnstable,
  ...
}:
{
  # ryzen_smu only exists for x86_64; the guard keeps the module inert on
  # other platforms so profiles that import every module still evaluate.
  config = lib.mkIf config.nixpkgs.hostPlatform.isx86_64 {
    hardware.cpu.amd.ryzen-smu.enable = true;
    # The upstream module hardcodes boot.kernelPackages.ryzen-smu with no
    # package option, so the driver has to be replaced inside the kernel
    # package set itself. nixpkgs assembles every per-kernel set through
    # linuxKernel.packagesFor (linuxPackages_latest included), so extending
    # that hook is what reaches whichever kernel the system selects. The
    # unstable driver expression is used because it tracks kernel API changes
    # faster than the stable one.
    nixpkgs.overlays = [
      (final: prev: {
        linuxKernel = prev.linuxKernel // {
          packagesFor =
            kernel:
            (prev.linuxKernel.packagesFor kernel).extend (
              _lpfinal: _lpprev: {
                ryzen-smu = (pkgsUnstable.linuxPackagesFor kernel).ryzen-smu;
              }
            );
        };
      })
    ];
  };
}

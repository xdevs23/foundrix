# Radxa ZERO 3E (Rockchip RK3566)
{
  foundrixModules,
  pkgs,
  lib,
  ...
}:
let
  # A literal, because the unfree allowlist is read while pkgs is being built
  ramSetupBinaryName = "rk3566-ddr-tpl";

  ramSetupBinary = pkgs.fetchurl rec {
    pname = ramSetupBinaryName;
    version = "1.26";
    url = "https://raw.githubusercontent.com/rockchip-linux/rkbin/3e288fe814e059dd06833495f845cab04ac20a5c/bin/rk35/rk3566_ddr_1056MHz_v${version}.bin";
    hash = "sha256-mWbCGq3wBzfM7ML61v48kC/yaVZDMCn3Df11nU9gYWo=";
    meta.license = lib.licenses.unfreeRedistributableFirmware;
  };

  # The U-Boot build for the ZERO 3W also boots the ZERO 3E: it tells the boards apart by ADC.
  uboot = pkgs.ubootRadxaZero3W.overrideAttrs (previous: {
    env = previous.env // {
      ROCKCHIP_TPL = ramSetupBinary;
    };
  });
in
{
  imports = [
    foundrixModules.config.image.boot.rockchip
    foundrixModules.config.image.device
  ];

  foundrix.config.image.boot.rockchip = {
    idbloader = "${uboot}/idbloader.img";
    uboot = "${uboot}/u-boot.itb";
  };
  foundrix.nixpkgs.allowedUnfreePackageNames = [ ramSetupBinaryName ];

  # The microSD card slot (sdmmc0)
  foundrix.config.image.device.rootDevice = lib.mkDefault "/dev/disk/by-path/platform-fe2b0000.mmc";

  hardware.deviceTree.name = "rockchip/rk3566-radxa-zero-3e.dtb";

  boot.kernelParams = [ "console=ttyS2,1500000n8" ];
}

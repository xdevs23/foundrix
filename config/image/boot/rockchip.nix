{
  config,
  pkgs,
  lib,
  namespaced,
  namespacedCfg,
  foundrixModules,
  ...
}:
let
  cfg = namespacedCfg __curPos;
  image = config.system.build.image;

  repartDefinitions = pkgs.runCommand "repart-definitions" { } ''
    cp --recursive "$(${image.amendRepartDefinitions} ${pkgs.writeText "partitions.json" image.partitionsJSON} ${image.definitionsDirectory})" $out
  '';

  definitionsFlag = "--definitions=${image.finalRepartDefinitions}";
  repartFlags =
    assert lib.assertMsg (lib.count (flag: flag == definitionsFlag) image.systemdRepartFlags == 1)
      "config.image.boot.rockchip expects ${definitionsFlag} exactly once in the systemd-repart flags set by the nixpkgs image builder. Update the flag replacement in this module to match nixos/modules/image/repart-image.nix.";
    map (
      flag: if flag == definitionsFlag then "--definitions=${repartDefinitions}" else flag
    ) image.systemdRepartFlags;
in
{
  imports = [
    foundrixModules.framework.repart-disk-image
  ];

  options = namespaced __curPos {
    idbloader = lib.mkOption {
      type = lib.types.pathInStore;
      description = "Pre-bootloader (idbloader.img) loaded by the boot ROM from sector 64";
    };
    uboot = lib.mkOption {
      type = lib.types.pathInStore;
      description = "U-Boot FIT image (u-boot.itb) written by rockflasher to the uboot partition at 8 MiB";
    };
  };

  config = {
    assertions = [
      {
        assertion = lib.elem config.image.repart.sectorSize [
          null
          512
        ];
        message = "config.image.boot.rockchip needs image.repart.sectorSize to be 512 or null, because rockflasher writes the partition table with 512-byte sectors. Remove the image.repart.sectorSize setting.";
      }
    ];

    # systemd-repart fails in an emulated build. build-sd-image packs the card outside of Nix instead.
    foundrix.traits.image.packedOutsideNix = true;

    system.build.sdImageDescription = (pkgs.formats.json { }).generate "sd-image-description.json" {
      rockflasherFlags = [
        "--idbloader"
        cfg.idbloader
        "--partition"
        "uboot:${cfg.uboot}"
      ];
      inherit repartFlags;
      environment = image.env;
    };
  };
}

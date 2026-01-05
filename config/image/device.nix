{
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  options = namespaced __curPos {
    rootDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Device path for the root/system disk where the image is flashed.
        When null, auto-detection will be attempted via volatile-root symlink.
        Examples: "/dev/nvme0n1", "/dev/disk/by-path/pci-0000:01:00.0-nvme-1"
      '';
    };

    dataDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = (namespacedCfg __curPos).rootDevice;
      defaultText = lib.literalExpression "config.foundrix.config.image.device.rootDevice";
      description = ''
        Device path for runtime data partitions (created via systemd-repart).
        Can be the same as rootDevice or a separate disk.
        When null, auto-detection will be attempted.
        Examples: "/dev/sdb", "/dev/disk/by-id/scsi-0HC_Volume_..."
      '';
    };
  };
}

{
  config,
  pkgs,
  lib,
  modulesPath,
  foundrixModules,
  installedOnly,
  ...
}:
let
  partitionIds = config.foundrix.config.image.partition-ids;
in
{
  imports = [
    "${modulesPath}/image/repart.nix"
    foundrixModules.framework.repart-disk-image
    foundrixModules.config.filesystem.nix
    ../partition-ids.nix
  ];

  config = installedOnly config {
    image.repart.compression.enable = lib.mkDefault true;

    image.repart.partitions.${partitionIds.main} = {
      storePaths = [ config.system.build.toplevel ];
      nixStorePrefix = "/nix/store";

      # Required for nix usability and home-manager compatibility
      contents."/nix/store/nix-path-registration".source = "${
        pkgs.closureInfo { rootPaths = [ config.system.build.toplevel ]; }
      }/registration";

      repartConfig = {
        Type = "linux-generic";
        Label = "main";
        Format = "btrfs";
        MakeDirectories = "/nix";
        Subvolumes = "/nix";
        Minimize = "guess";
        SplitName = "main";
      };
    };

    # Default /nix filesystem config pointing to main partition
    foundrix.config.filesystem.nix = {
      device = lib.mkDefault "/dev/disk/by-partlabel/${config.image.repart.partitions.${partitionIds.main}.repartConfig.Label}";
      fsOptions = lib.mkDefault [
        "subvol=nix"
        "compress=zstd"
      ];
    };

    fileSystems."/nix".neededForBoot = lib.mkDefault true;

    environment.systemPackages = [ pkgs.btrfs-progs ];

    boot.initrd.supportedFilesystems.btrfs = true;
    boot.supportedFilesystems.btrfs = true;
  };
}

{
  config,
  pkgs,
  lib,
  modulesPath,
  foundrixModules,
  installedOnly,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = namespacedCfg __curPos;
  partitionIds = config.foundrix.config.image.partition-ids;
  storeSubvolume = "nix";
  subvolumePaths = lib.concatMapStringsSep " " (name: "/${name}") (
    [ storeSubvolume ] ++ cfg.extraSubvolumes
  );
in
{
  imports = [
    "${modulesPath}/image/repart.nix"
    foundrixModules.framework.repart-disk-image
    foundrixModules.config.filesystem.nix
    ../partition-ids.nix
  ];

  options = namespaced __curPos {
    extraSubvolumes = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[^/]+");
      default = [ ];
      example = [ "var" ];
      description = "Names of the subvolumes created by the image on the main btrfs partition next to the nix subvolume";
    };
  };

  config = installedOnly config {
    # Disabled by default: the btrfs filesystem itself already does zstd
    # compression (see fsOptions below), so artifact-level compression is
    # redundant for local image builds. Devices that distribute images over
    # the network can opt back in by setting this to true.
    image.repart.compression.enable = lib.mkDefault false;

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
        MakeDirectories = subvolumePaths;
        Subvolumes = subvolumePaths;
        Minimize = "guess";
        SplitName = "main";
      };
    };

    # Default /nix filesystem config pointing to main partition
    foundrix.config.filesystem.nix = {
      device = lib.mkDefault "/dev/disk/by-partlabel/${
        config.image.repart.partitions.${partitionIds.main}.repartConfig.Label
      }";
      fsOptions = lib.mkDefault [
        "subvol=${storeSubvolume}"
        "compress=zstd"
      ];
    };

    fileSystems."/nix".neededForBoot = lib.mkDefault true;

    environment.systemPackages = [ pkgs.btrfs-progs ];

    boot.initrd.supportedFilesystems.btrfs = true;
    boot.supportedFilesystems.btrfs = true;
  };
}

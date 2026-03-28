# Dynamic device discovery
#
# Creates stable symlinks at /dev/dynamic/<name>-<index> for block devices
# matching a glob pattern. Useful when the exact device path varies between
# environments (e.g. Hetzner Cloud volume IDs).
#
# Usage:
#   foundrix.config.device.dynamic.hetzner-data.glob = "/dev/disk/by-id/scsi-0HC_Volume_*";
#   foundrix.config.image.device.dataDevice = "/dev/dynamic/hetzner-data-0";
#
{
  config,
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
let
  cfg = (namespacedCfg __curPos);

  # Build udev rules from dynamic device configs
  mkUdevRule =
    name: devCfg:
    let
      indices = lib.genList (i: i) devCfg.count;
      # For count=1: simple rule with SYMLINK
      # For count>1: use a RUN script to assign indices
      simpleRule = ''
        # Dynamic device: ${name} (glob: ${devCfg.glob})
        ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{DEVLINKS}=="*${devCfg.glob}", SYMLINK+="dynamic/${name}-0", TAG+="systemd"
      '';
    in
    simpleRule;

  allRules = lib.concatStringsSep "\n" (lib.mapAttrsToList mkUdevRule cfg);
in
{
  options = namespaced __curPos (
    lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            glob = lib.mkOption {
              type = lib.types.str;
              description = ''
                Glob pattern to match block devices.
                Must be a path under /dev/ (e.g. /dev/disk/by-id/scsi-0HC_Volume_*).
                The pattern is matched against udev DEVLINKS using fnmatch.
              '';
              example = "/dev/disk/by-id/scsi-0HC_Volume_*";
            };
            count = lib.mkOption {
              type = lib.types.int;
              default = 1;
              description = ''
                Number of matching devices to expose.
                Creates symlinks <name>-0 through <name>-<count-1> under /dev/dynamic/.
                Currently only count=1 is supported.
              '';
            };
          };
        }
      );
      default = { };
      description = ''
        Dynamic device discovery via udev.
        Each entry creates a stable symlink at /dev/dynamic/<name>-<index> for
        block devices whose DEVLINKS match the configured glob pattern.

        This is useful when the exact device identifier varies across environments
        but follows a predictable naming pattern. The created symlinks can be
        referenced in foundrix.config.image.device.dataDevice and similar options.
      '';
    }
  );

  config = lib.mkIf (cfg != { }) {
    assertions = lib.mapAttrsToList (name: devCfg: {
      assertion = devCfg.count == 1;
      message = "foundrix.config.device.dynamic.${name}.count > 1 is not yet supported";
    }) cfg;

    # Main system udev rules
    services.udev.extraRules = allRules;

    # Initrd udev rules (for boot-time systemd-repart)
    boot.initrd.services.udev.rules = allRules;
  };
}

# Trait type constants for enum-based traits.
# These are passed to modules via _module.args.traitTypes
{
  filesystem = {
    rootType = {
      volatile = "volatile";
      readonly = "readonly";
      persistent = "persistent";
    };
    varProvisioner = {
      repart = "repart";
      luks-manager = "luks-manager";
    };
  };
  homeManager = {
    method = {
      prebuilt = "prebuilt";
      runtime = "runtime";
    };
  };
  image = {
    updateMethod = {
      none = "none";
      systemd-sysupdate = "systemd-sysupdate";
    };
  };
  system = {
    purpose = {
      installed = "installed";
      live = "live";
    };
  };

  # Variant descriptions for display purposes
  descriptions = {
    filesystem = {
      rootType = {
        volatile = "tmpfs - state must be persisted elsewhere";
        readonly = "erofs/squashfs - immutable root";
        persistent = "btrfs/ext4 - normal persistent root";
      };
      varProvisioner = {
        repart = "systemd-repart creates/grows the var partition in the initrd";
        luks-manager = "var-disk-manager provides /var as LUKS2-encrypted btrfs";
      };
    };
    homeManager = {
      method = {
        prebuilt = "pre-built, no runtime evaluation needed";
        runtime = "evaluated at runtime/activation";
      };
    };
    image = {
      updateMethod = {
        none = "no system updates - static partition labels";
        systemd-sysupdate = "A/B updates with versioned partition labels";
      };
    };
    system = {
      purpose = {
        installed = "permanently installed system with persistent storage";
        live = "ephemeral live system - no runtime partitioning or persistent mounts";
      };
    };
  };
}

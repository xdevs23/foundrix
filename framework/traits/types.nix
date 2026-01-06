# Trait type constants for enum-based traits.
# These are passed to modules via _module.args.traitTypes
{
  filesystem = {
    rootType = {
      volatile = "volatile";
      readonly = "readonly";
      persistent = "persistent";
    };
  };
  homeManager = {
    method = {
      prebuilt = "prebuilt";
      runtime = "runtime";
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
    };
    homeManager = {
      method = {
        prebuilt = "pre-built, no runtime evaluation needed";
        runtime = "evaluated at runtime/activation";
      };
    };
  };
}

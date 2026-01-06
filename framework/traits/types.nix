# Trait type constants for enum-based traits.
# These are passed to modules via _module.args.traitTypes
{
  filesystem = {
    rootType = {
      volatile = "volatile"; # tmpfs - state must be persisted elsewhere
      readonly = "readonly"; # erofs/squashfs - immutable root
      persistent = "persistent"; # btrfs/ext4 - normal persistent root
    };
  };
}

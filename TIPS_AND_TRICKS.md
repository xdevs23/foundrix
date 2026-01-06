# Foundrix Tips and Tricks

Tips, commands, and gotchas for working with the foundrix codebase. Useful for humans and coding agents.

## Nix Commands for Development

### Exploring the Flake

See all available outputs (configurations, checks, packages, modules):
```bash
nix flake show path:.
```

### Listing Available Modules

Pretty tree view with colors:
```bash
nix eval --raw 'path:.#show-modules'
```

Flat list (useful for grepping):
```bash
nix eval --raw 'path:.#list-modules'
```

Filter for specific modules:
```bash
nix eval --raw 'path:.#list-modules' | grep image
```

### Showing Traits

Show enabled traits for a configuration with descriptions:
```bash
nix eval --raw 'path:.#show-traits.smoke-test-server-writable'
```

Show all traits (enabled and disabled):
```bash
nix eval --raw 'path:.#show-all-traits.smoke-test-server-writable'
```

### Working with Uncommitted Changes

**Important**: When working with uncommitted changes, always use `path:.#` instead of `.#`:

```bash
# CORRECT - uses uncommitted changes
nix eval 'path:.#nixosModules.config.image.device'

# WRONG - only sees committed changes
nix eval '.#nixosModules.config.image.device'
```

This applies to all nix commands:
```bash
nix flake show path:.
nix build 'path:.#nixosConfigurations.smoke-test'
nix eval 'path:.#list-modules'
```

### Evaluating Configuration Values

Check partition definitions:
```bash
nix eval 'path:.#nixosConfigurations.smoke-test-server-writable.config.image.repart.partitions' --apply 'x: builtins.attrNames x'
```

Check runtime repart partitions:
```bash
nix eval 'path:.#nixosConfigurations.smoke-test-server-writable.config.systemd.repart.partitions' --apply 'x: builtins.attrNames x'
```

## Foundrix Design Principles

### Import-Based Enablement

**Key Principle**: Features are enabled by importing the respective module, NOT via `enable` options.

```nix
# CORRECT - import to enable
imports = [ foundrixModules.config.image.slots.ab ];

# WRONG - foundrix doesn't use enable options for feature selection
foundrix.config.image.slots.layout = "ab";
```

Options are only for **configurable values** (device paths, sizes, timeouts), not feature selection.

### Module Options Pattern (`namespaced`)

Foundrix uses `namespaced` and `namespacedCfg` for auto-namespaced options based on file path:

```nix
{
  lib,
  namespaced,
  namespacedCfg,
  ...
}:
{
  # Options are auto-namespaced based on file location
  # e.g., config/image/device.nix -> foundrix.config.image.device.*
  options = namespaced __curPos {
    myOption = lib.mkOption { ... };
  };

  config =
    let
      cfg = namespacedCfg __curPos;
    in
    {
      # Use cfg.myOption to access the value
    };
}
```

### Accessing Other Module's Config

To access config from another foundrix module, use the full path:

```nix
let
  partitionIds = config.foundrix.config.image.partition-ids;
in
{
  image.repart.partitions.${partitionIds.main} = { ... };
}
```

### stateVersion in Profiles

Profiles should set `system.stateVersion`:

```nix
{
  lib,
  ...
}:
{
  system.stateVersion = lib.mkDefault (builtins.substring 0 5 lib.version);
}
```

## Module Discovery

Modules are automatically discovered from these directories:
- `./components`
- `./config`
- `./framework`
- `./hardware`
- `./profiles`
- `./services`

The flake.nix `processDirectoryRecursive` function:
- Recursively processes all `.nix` files (except `default.nix`)
- Creates nested attribute sets matching directory structure
- e.g., `config/image/boot/systemd-boot.nix` → `foundrixModules.config.image.boot.systemd-boot`

## Smoke Tests

### Existing Smoke Test

The main smoke test is at `nixosConfigurations.smoke-test` and imports `profiles.all-modules`.

### Adding New Smoke Tests

Add to flake.nix under `nixosConfigurations`:

```nix
smoke-test-my-feature = lib.nixosSystem {
  specialArgs = self.nixosModules.foundrixSpecialArgs;
  modules = [
    ./common
    self.nixosModules.profiles.my-profile
    {
      nixpkgs.hostPlatform = lib.mkOverride 1200 "x86_64-linux";
      # Required config for the modules being tested
    }
  ];
};
```

## Image Store Configuration

### nixStorePrefix Explained

The `nixStorePrefix` option in `image.repart.partitions` controls where nix store contents are placed within the partition:

| nixStorePrefix | Contents in partition | Partition mount point |
|----------------|----------------------|----------------------|
| `/nix/store` | `nix/store/...` | `/` or btrfs subvol |
| `/` | `...` (store at root) | `/nix/store` |

**btrfs-writable** uses `/nix/store` - the partition contains a full filesystem tree with nix store inside, mounted with subvolume options.

**erofs-readonly** uses `/` - the partition IS the nix store, mounted directly to `/nix/store`.

### erofs Read-Only Store

For read-only systems (HTPCs, appliances), use erofs:
- Compressed (lz4hc by default)
- Fast random reads
- No runtime modification possible

Requires `system.image.version` for partition labeling:
```nix
system.image.version = "1";
```

### A/B Slot Layout

The `slots.ab` module adds an empty store partition for atomic updates:
- Active slot: `30-store` with label `store_${version}`
- Empty slot: `35-store-empty` with label `_empty`

systemd-sysupdate writes to the empty slot, then reboots into it.

## Common Gotchas

### boot.initrd.systemd.enable Required

If using `boot.initrd.systemd.repart`, you must also enable:
```nix
boot.initrd.systemd.enable = true;
```

### Partition IDs

Partition IDs use systemd-repart naming convention with numeric prefixes for ordering:
- `10-esp` - EFI System Partition
- `20-main` - Main system partition
- `30-store` - Read-only store
- `50-var` - Runtime /var partition

### Device Paths

Always use stable device paths:
- `/dev/disk/by-id/...` - Stable across reboots
- `/dev/disk/by-path/...` - PCI path-based
- `/dev/disk/by-partuuid/...` - Partition UUID
- `/dev/disk/by-partlabel/...` - GPT partition label

Avoid `/dev/sdX` or `/dev/nvmeXnY` as these can change.

## Nix Language Tips

### Avoid Shadowing Builtins

Don't use variable names that shadow Nix builtins like `path`, `map`, `toString`, etc.:

```nix
# BAD - shadows builtin
map (path: { ... }) paths

# GOOD - use descriptive names
map (filePath: { ... }) paths
map (modulePath: { ... }) modules
map (dirPath: { ... }) directories
```

### Use Prelude Builtins Without Prefix

These builtins are in the prelude and don't need the `builtins.` prefix:

```nix
# Unnecessary prefix
builtins.map
builtins.removeAttrs
builtins.toString

# Cleaner
map
removeAttrs
toString
```

### Pattern Matching in Function Arguments

Nix doesn't support renaming in pattern destructuring like `{ path = newName, ... }`. Instead:

```nix
# BAD - syntax error
map ({ path = filePath, name, ... }: ...) items

# GOOD - use the whole item
map (item: let filePath = item.path; in ...) items

# GOOD - or just use the original name if it doesn't shadow
map ({ path, name, ... }: ...) items
```

### Circular Import Prevention

When importing modules from `common/`, don't use `foundrixModules` as it wraps modules with common imports (circular dependency). Use direct paths instead:

```nix
# BAD - circular import
imports = [ foundrixModules.framework.traits ];

# GOOD - direct path
imports = [ (foundrix + "/framework/traits") ];

# GOOD - relative path within same repo
imports = [ ./traits.nix ];
```

## Module System Tips

### Passing Arguments to All Modules

Use `_module.args` in `common/` to make values available to all modules:

```nix
# common/default.nix
config._module.args.traitTypes = import (foundrix + "/framework/traits/types.nix");

# Any module can then use it
{ traitTypes, ... }:
{
  config.foo = traitTypes.filesystem.rootType.volatile;
}
```

### Accessing Options vs Config

- `config.foo.bar` - The resolved value after all modules are evaluated
- `options.foo.bar` - The option definition (type, default, description)
- `options.foo.bar.description` - Get the description string from an option

### Enum Options with Null Default

For optional enum traits, use `nullOr`:

```nix
type = lib.types.nullOr (lib.types.enum [ "a" "b" "c" ]);
default = null;
```

This allows distinguishing "not set" from any valid enum value.

## DRY Principles

### Don't Duplicate Descriptions

- **Option descriptions**: Define in the `lib.mkOption` call
- **Enum variant descriptions**: Define in a central location (e.g., `traitTypes.descriptions`)
- **Display logic**: Pull from source of truth, don't hardcode

```nix
# BAD - duplicated
traitDescriptions = {
  foo = "Description here";  # Duplicates option description
};

# GOOD - single source of truth
# Description in option definition, display code reads from options
description = options.foundrix.traits.foo.description;
```

### Constants Outside Option System

For enum values used across modules, define constants separately from options:

```nix
# framework/traits/types.nix
{
  filesystem.rootType = {
    volatile = "volatile";
    readonly = "readonly";
  };
}

# Passed via _module.args, used everywhere
config.foo = traitTypes.filesystem.rootType.volatile;
```

## File Structure Reference

```
foundrix/
├── config/
│   ├── image/                    # Image-time configuration
│   │   ├── boot/
│   │   │   ├── systemd-boot.nix      # UEFI boot
│   │   │   └── systemd-boot-bios.nix # UEFI + BIOS fallback
│   │   ├── store/
│   │   │   ├── btrfs-writable.nix    # Writable nix store
│   │   │   └── erofs-readonly.nix    # Read-only nix store
│   │   ├── slots/
│   │   │   └── ab.nix                # A/B slot layout
│   │   ├── device.nix                # Device path options
│   │   └── partition-ids.nix         # Partition ID constants
│   ├── runtime/                  # Runtime partitioning
│   │   └── repart/
│   │       ├── var.nix               # /var for servers
│   │       └── data.nix              # Generic data partition
│   └── filesystem/               # Mount configurations
│       ├── nix.nix                   # /nix mount (btrfs)
│       ├── nix-store-erofs.nix       # /nix/store mount (erofs)
│       └── var.nix                   # /var mount
├── profiles/
│   └── image/                    # High-level image profiles
│       ├── server-writable.nix       # Writable server
│       └── readonly-ab.nix           # Read-only with A/B
├── framework/                    # Build frameworks
└── flake.nix
```

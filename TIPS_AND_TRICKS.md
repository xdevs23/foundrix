# Foundrix Tips and Tricks

Tips, commands, and gotchas for working with the foundrix codebase. Useful for humans and coding agents.

## Nix Commands for Development

### Listing Available Modules

Use the built-in `list-modules` output to see all available foundrix modules:

```bash
nix eval --raw 'path:.#list-modules'
```

Filter for specific modules:
```bash
nix eval --raw 'path:.#list-modules' | grep image
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

## File Structure Reference

```
foundrix/
├── config/
│   ├── image/           # Image-time configuration
│   │   ├── boot/        # Boot loader modules
│   │   ├── store/       # Nix store partition types
│   │   ├── device.nix   # Device selection options
│   │   └── partition-ids.nix
│   ├── runtime/         # Runtime partitioning
│   │   └── repart/      # systemd-repart modules
│   └── filesystem/      # Mount configurations
├── profiles/
│   └── image/           # High-level image profiles
├── framework/           # Build frameworks
└── flake.nix
```

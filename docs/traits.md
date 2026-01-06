# Foundrix Trait System

Traits are cross-module capability announcements that allow modules to advertise their characteristics and let other modules react accordingly.

## Overview

The trait system solves the problem of modules needing to know about each other's capabilities without creating tight coupling. For example, when root is on tmpfs, the `/var` module needs to enable persistence - but it shouldn't need to import or know about the tmpfs module directly.

## Using Traits

### Viewing Traits

Show enabled traits for a configuration:
```bash
nix eval --raw 'path:.#show-traits.smoke-test-server-writable'
```

Show all traits (enabled and disabled):
```bash
nix eval --raw 'path:.#show-all-traits.smoke-test-server-writable'
```

### Trait Types

#### Boolean Traits

Simple on/off capabilities:

```nix
# Definition in framework/traits/filesystem.nix
options.foundrix.traits.filesystem = {
  readOnlyStore = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Nix store is read-only (erofs) and cannot be modified at runtime";
  };
};

# Setting a trait (in the module that provides the capability)
config.foundrix.traits.filesystem.readOnlyStore = true;

# Consuming a trait (in modules that react to the capability)
let
  readOnlyStore = config.foundrix.traits.filesystem.readOnlyStore or false;
in
{
  # Adjust behavior based on trait
}
```

#### Enum Traits

Mutually exclusive states where only one can be active:

```nix
# Definition in framework/traits/filesystem.nix
options.foundrix.traits.filesystem = {
  rootType = lib.mkOption {
    type = lib.types.nullOr (lib.types.enum (builtins.attrValues traitTypes.filesystem.rootType));
    default = null;
    description = "Root filesystem type - determines persistence and mutability characteristics";
  };
};

# Setting a trait
config.foundrix.traits.filesystem.rootType = traitTypes.filesystem.rootType.volatile;

# Consuming a trait
let
  rootType = config.foundrix.traits.filesystem.rootType or null;
  isVolatileRoot = rootType == traitTypes.filesystem.rootType.volatile;
in
{
  # Adjust behavior based on trait
}
```

## Trait Type Constants

Enum values are defined in `framework/traits/types.nix`:

```nix
{
  filesystem = {
    rootType = {
      volatile = "volatile";     # tmpfs - state must be persisted elsewhere
      readonly = "readonly";     # erofs/squashfs - immutable root
      persistent = "persistent"; # btrfs/ext4 - normal persistent root
    };
  };
  homeManager = {
    method = {
      prebuilt = "prebuilt";  # pre-built, no runtime evaluation
      runtime = "runtime";    # evaluated at runtime/activation
    };
  };

  # Variant descriptions for display (used by show-traits)
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
```

These constants are available via `_module.args.traitTypes` in all modules.

## Available Traits

### filesystem.rootType (enum)

Root filesystem type - determines persistence and mutability characteristics.

| Value | Description |
|-------|-------------|
| `volatile` | tmpfs - state must be persisted elsewhere |
| `readonly` | erofs/squashfs - immutable root |
| `persistent` | btrfs/ext4 - normal persistent root |
| `null` | Not set (default) |

**Set by**: `config.filesystem.root-tmpfs` (volatile)

**Consumed by**: `config.filesystem.var` (enables persistence options when volatile)

### filesystem.readOnlyStore (bool)

Nix store is read-only (erofs) and cannot be modified at runtime.

**Set by**: `config.image.store.erofs-readonly`

### homeManager.method (enum)

Home Manager evaluation method. `null` means Home Manager is not present.

| Value | Description |
|-------|-------------|
| `prebuilt` | Pre-built configurations, no runtime evaluation needed |
| `runtime` | Evaluated at runtime/activation |
| `null` | Home Manager not present (default) |

**Set by**: `config.home-manager` (runtime)

**Consumed by**: `config.filesystem.nix`, `config.filesystem.home-tmpfs` (add mount dependencies)

## Creating New Traits

### 1. Add to types.nix (for enums)

```nix
# framework/traits/types.nix
{
  myCategory = {
    myTrait = {
      option1 = "option1";
      option2 = "option2";
    };
  };

  descriptions = {
    myCategory = {
      myTrait = {
        option1 = "Description for option1";
        option2 = "Description for option2";
      };
    };
  };
}
```

### 2. Create trait module

```nix
# framework/traits/my-category.nix
{
  lib,
  traitTypes,  # Only needed for enum traits
  ...
}:
{
  options.foundrix.traits.myCategory = {
    # Boolean trait
    myBoolTrait = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Description of the trait";
    };

    # Enum trait
    myEnumTrait = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (builtins.attrValues traitTypes.myCategory.myTrait));
      default = null;
      description = "Description of the trait";
    };
  };
}
```

### 3. Add to default.nix

```nix
# framework/traits/default.nix
{ ... }:
{
  imports = [
    ./filesystem.nix
    ./home-manager.nix
    ./my-category.nix  # Add new trait module
  ];
}
```

### 4. Set trait in capability module

```nix
# config/my-feature.nix
{
  config,
  traitTypes,
  ...
}:
{
  config = {
    # Announce the trait
    foundrix.traits.myCategory.myEnumTrait = traitTypes.myCategory.myTrait.option1;

    # ... rest of module config
  };
}
```

### 5. Consume trait in dependent modules

```nix
# config/dependent-module.nix
{
  config,
  traitTypes,
  ...
}:
let
  myTrait = config.foundrix.traits.myCategory.myEnumTrait or null;
  isOption1 = myTrait == traitTypes.myCategory.myTrait.option1;
in
{
  config = {
    someOption = lib.mkDefault isOption1;
  };
}
```

## Design Principles

1. **Traits are announcements, not configuration** - A trait says "I have this capability", it doesn't configure that capability.

2. **Graceful degradation** - Always use `or` when consuming traits to handle cases where the trait module isn't imported:
   ```nix
   config.foundrix.traits.foo.bar or false
   config.foundrix.traits.foo.baz or null
   ```

3. **DRY descriptions** - Option descriptions live in the option definition. Enum variant descriptions live in `traitTypes.descriptions`.

4. **Null means unset for enums** - Use `lib.types.nullOr` for enum traits so `null` represents "not configured".

5. **All traits always visible** - The `show-all-traits` output shows all defined traits regardless of which modules are imported, because all trait modules are imported via `common/`.

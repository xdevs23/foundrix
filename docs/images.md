# Building Disk Images with Foundrix

Build bootable disk images for servers, edge devices, and appliances using Foundrix's modular partitioning system.

## Quick Start

Create a new project using the `server-writable` template:

```bash
nix flake new my-server -t git+https://codeberg.org/xdevs23/foundrix#server-writable
cd my-server
```

Edit `devices/my-server/default.nix` and set your data device path:

```nix
foundrix.config.image.device.dataDevice = "/dev/disk/by-id/your-disk-id";
```

Build the image:

```bash
nix build path:.#packages.x86_64-linux.nixos-headless/image:my-server:x86_64
```

Or use `nix flake show path:.` to see all available outputs.

## What You Get

The `server-writable` profile provides:

- **Writable btrfs nix store** - Use `nix build`, `nix shell`, `nixos-rebuild`
- **UEFI + BIOS boot** - systemd-boot for UEFI, syslinux fallback for legacy BIOS
- **Runtime /var partition** - Created on first boot via systemd-repart
- **Ephemeral root** - tmpfs root that resets on reboot

## Module Architecture

Foundrix separates concerns into composable modules:

```
┌─────────────────────────────────────────────────────────────┐
│ profiles.image.server-writable                              │
│   └─ config.image.store.btrfs-writable (nix store partition)│
│   └─ config.image.boot.systemd-boot-bios (ESP + bootloader) │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ config.runtime.repart.var (/var at runtime)                 │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│ config.filesystem.* (mount configuration)                   │
│   └─ root-tmpfs, esp, nix, var, home-tmpfs                  │
└─────────────────────────────────────────────────────────────┘
```

The profile imports lower-level modules. You can compose your own profile by importing modules directly.

## Key Options

### Device Paths

```nix
# Required: where runtime partitions go
foundrix.config.image.device.dataDevice = "/dev/disk/by-id/...";

# Optional: separate system disk (defaults to dataDevice)
foundrix.config.image.device.rootDevice = "/dev/disk/by-id/...";
```

Always use stable paths (`/dev/disk/by-id/`, `/dev/disk/by-path/`), not `/dev/sdX`.

### Boot

```nix
foundrix.config.image.boot.systemd-boot.timeout = 1;  # seconds
```

### Runtime /var

```nix
foundrix.config.runtime.repart.var.format = "btrfs";  # default
foundrix.config.runtime.repart.var.sizeMin = "4G";    # default: 1G
```

### Persistence

```nix
foundrix.config.filesystem.var.persistMachineId = true;
foundrix.config.filesystem.var.persistSshHostKeys = true;
```

## Partition Layout

```
System disk (image):
├── 10-esp (FAT32)     ← EFI + syslinux bootloader
└── 20-main (btrfs)    ← /nix subvolume

Data disk (runtime):
└── 50-var (btrfs)     ← /var subvolume (created on first boot)
```

## Read-Only Profile (readonly-ab)

For appliances that don't need runtime package installation:

```nix
imports = [
  foundrixModules.profiles.image.readonly-ab
  foundrixModules.config.runtime.repart.data
  foundrixModules.config.filesystem.root-tmpfs
  foundrixModules.config.filesystem.var
  foundrixModules.config.filesystem.home-tmpfs
];

foundrix.config.image.device.dataDevice = "/dev/nvme0n1";
system.image.version = "1";  # Required for A/B slot labeling
```

**Partition layout:**
```
System disk (image):
├── 10-esp (FAT32)           ← EFI bootloader
├── 30-store (erofs)         ← Read-only /nix/store
└── 35-store-empty           ← Empty A/B slot for updates

Data disk (runtime):
└── 21-data (btrfs)          ← /var (created on first boot)
```

## Available Modules

### Profiles

| Module | Description |
|--------|-------------|
| `profiles.image.server-writable` | Writable btrfs store + UEFI/BIOS boot |
| `profiles.image.readonly-ab` | Read-only erofs store + A/B slots + UEFI |

### Store Types

| Module | Description |
|--------|-------------|
| `config.image.store.btrfs-writable` | Writable btrfs nix store |
| `config.image.store.erofs-readonly` | Read-only erofs nix store |

### Boot

| Module | Description |
|--------|-------------|
| `config.image.boot.systemd-boot` | UEFI boot with systemd-boot |
| `config.image.boot.systemd-boot-bios` | UEFI + syslinux BIOS fallback |

### Slots

| Module | Description |
|--------|-------------|
| `config.image.slots.ab` | A/B slot layout for atomic updates |

### Runtime Partitioning

| Module | Description |
|--------|-------------|
| `config.runtime.repart.var` | /var partition (servers) |
| `config.runtime.repart.data` | Generic data partition (appliances) |

### Filesystems

| Module | Description |
|--------|-------------|
| `config.filesystem.root-tmpfs` | Ephemeral root on tmpfs |
| `config.filesystem.esp` | EFI System Partition mount |
| `config.filesystem.nix` | /nix mount (btrfs) |
| `config.filesystem.nix-store-erofs` | /nix/store mount (erofs) |
| `config.filesystem.var` | /var mount with persistence |
| `config.filesystem.home-tmpfs` | Ephemeral /home on tmpfs |


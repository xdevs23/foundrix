# Foundrix for NixOS

**Foundrix** is a collection of composable NixOS modules designed as building blocks for production-ready, declarative system configuration.

## Key Features

- **Composable**: Mix and match modules to build exactly what you need
- **Profiles**: Handcrafted profiles to reduce boilerplate in common setups
- **Templates**: Get started in no time
- **A-only systems**: For writable systems with standard updates
- **A/B atomic updates**: Fail-safe system updates with automatic rollback (WIP)
- **Secure boot**: Custom keys or RedHat shim with MOK for custom OS verification (WIP)
- **Flexible Nix store**: Read-only and read-write configurations
- **Home Manager support**: Works on regular writable NixOS and read-only systems without runtime burden
- **Optional encryption**: TPM2 support secured through secure boot chain (WIP)
- **Multi-architecture**: x86_64, aarch64, riscv64 (WIP) support
- **Modern updates**: systemd-sysupdate integration for reliable OTA deployments (WIP)

## Quick Example

```nix
{
  imports = [
    foundrixModules.profiles.desktop-full
    foundrixModules.config.shell.zsh.lite
    foundrixModules.config.virtd
    foundrixModules.config.adb
    foundrixModules.config.linux.sysrq
    foundrixModules.config.virtualisation.docker
    foundrixModules.config.graphics.cursors.breezex-rosepine
    foundrixModules.config.graphics.fonts.adwaita-sans
    foundrixModules.config.home-jdk
    foundrixModules.components.llama-cpp
  ];
}
```

Perfect for managing fleets of edge devices, embedded systems, kiosks, or personal systems requiring reliable, maintainable, and secure NixOS deployments.

## Advanced Capabilities

- **Atomic System Updates**: A/B partition layouts for fail-safe updates with automatic rollback (WIP)
- **Secure Boot Chain**: Full UEFI secure boot with custom keys or RedHat shim with MOK for custom OS verification (WIP)
- **Ephemeral Systems**: Stateless, immutable systems that reset on reboot
- **Tmpfs Root**: Root filesystem on tmpfs with flexible Nix store configurations (read-only or writable)
- **OTA Updates**: Over-the-air updates via systemd-sysupdate for remote deployments (WIP)
- **TPM2 Encryption**: Optional disk encryption secured through the secure boot chain (WIP)
- **Multi-Architecture**: Native support for x86_64, aarch64, and riscv64 (WIP) platforms

## Getting Started

### Using templates

Create a new project using a template of your choice.

For example, for a Desktop PC:

```
nix flake new my-os -t git+https://codeberg.org/xdevs23/foundrix.git#desktop-pc
```

Customize to your liking by reading into the `flake.nix` and `configuration.nix`.

Check what is available via `nix flake show path:.`

You can list all available modules using either

```
nix eval --refresh --raw git+https://codeberg.org/xdevs23/foundrix#show-modules
```

or

```
nix eval --refresh --raw git+https://codeberg.org/xdevs23/foundrix#list-modules
```

## Documentation

Option documentation can be built and launched in your browser using

```
nix run --refresh git+https://codeberg.org/xdevs23/foundrix#docs
```

## Licensing

- **GNU Lesser General Public License v3.0 (LGPL-3.0)** - See [COPYING](COPYING)
- **Commercial License** - Perpetual license for one revision of your choice with one-time payment. Future revisions require separate licensing. For third party support, contact for options. Contact: TODO
  - Note: The free software LGPL-3.0 license represents the recommended licensing option for most use cases, providing both cost-effective implementation and adherence to established free software principles. Organizations considering commercial licensing should evaluate whether proprietary licensing terms align with their operational requirements and community engagement objectives. The copyright holder recognizes that specific scenarios may present operational constraints with free software compliance frameworks, and commercial licensing is provided as an accommodation for such circumstances.

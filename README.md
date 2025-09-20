# Foundrix for NixOS

**Foundrix** is a collection of composable NixOS modules designed as building blocks for production-ready, declarative system configuration.

## Key Features

- **Composable**: Mix and match modules to build exactly what you need
- **Production-ready**: Battle-tested configurations for real-world deployments
- **A-only systems**: For writable systems with standard updates
- **A/B atomic updates**: Fail-safe system updates with automatic rollback
- **Secure boot**: Custom keys or RedHat shim with MOK for custom OS verification
- **Flexible Nix store**: Read-only and read-write configurations
- **Home Manager support**: Works on regular writable NixOS and read-only systems without runtime burden
- **Optional encryption**: TPM2 support secured through secure boot chain
- **Multi-architecture**: x86_64, arm64, riscv64 support
- **Modern updates**: systemd-sysupdate integration for reliable OTA deployments

## Quick Example

```nix
{
  imports = [
    "${inputs.foundrix}/modules/hardware/generic/any/ahci.nix"
    "${inputs.foundrix}/modules/components/bootloaders/systemd-boot.nix"
    "${inputs.foundrix}/modules/components/networking/systemd-networkd.nix"
    "${inputs.foundrix}/modules/filesystem/tmpfs-root.nix"
    "${inputs.foundrix}/modules/partition/layouts/ab.nix"
    "${inputs.foundrix}/modules/ota/systemd-sysupdate.nix"
  ];
}
```

Perfect for managing fleets of edge devices, embedded systems, kiosks, or personal systems requiring reliable, maintainable, and secure NixOS deployments.

## Advanced Capabilities

- **Atomic System Updates**: A/B partition layouts for fail-safe updates with automatic rollback
- **Secure Boot Chain**: Full UEFI secure boot with custom keys or RedHat shim with MOK for custom OS verification
- **Ephemeral Systems**: Stateless, immutable systems that reset on reboot
- **Tmpfs Root**: Root filesystem on tmpfs with flexible Nix store configurations (read-only or writable)
- **OTA Updates**: Over-the-air updates via systemd-sysupdate for remote deployments
- **TPM2 Encryption**: Optional disk encryption secured through the secure boot chain
- **Multi-Architecture**: Native support for x86_64, arm64, and riscv64 platforms

## Getting Started

### Using with Flakes (Recommended)

> TODO

### Using with Channels

> TODO

## Licensing

- **GNU Lesser General Public License v3.0 (LGPL-3.0)** - See [COPYING](COPYING)
- **Commercial License** - Perpetual license for one revision of your choice with one-time payment. Future revisions require separate licensing. For third party support, contact for options. Contact: TODO
  - Note: The free software LGPL-3.0 license represents the recommended licensing option for most use cases, providing both cost-effective implementation and adherence to established free software principles. Organizations considering commercial licensing should evaluate whether proprietary licensing terms align with their operational requirements and community engagement objectives. The copyright holder recognizes that specific scenarios may present operational constraints with free software compliance frameworks, and commercial licensing is provided as an accommodation for such circumstances.

# Agent Guide

Conventions and gotchas for working in this repository. Read the linked docs
before making related changes.

## Supporting multiple NixOS releases

Foundrix supports two releases: NixOS 26.05 and nixos-unstable. No code or
version check is kept or added for any other release. When an option, default,
or library function only exists or only changed on nixos-unstable, check it
with `lib.versionAtLeast lib.version "<threshold>"` so the module still
evaluates on NixOS 26.05. Set legacy values explicitly to silence
state-version-gated warnings without changing behavior.

See [docs/release-compat.md](docs/release-compat.md) for the idiom, the
threshold to use, when a check is not needed, and how to remove checks once a
release leaves the supported list.

## Other references

- [docs/traits.md](docs/traits.md) — cross-module capability announcements
- [docs/var-luks.md](docs/var-luks.md) — encrypted /var (LUKS2) with automatic migration
- [docs/backup.md](docs/backup.md) — snapshot/replicate a subvolume to pluggable destinations
- [docs/intel-gpu.md](docs/intel-gpu.md) — the Level Zero driver with its compiler and ray tracing library
- [docs/images.md](docs/images.md) — image build/output conventions
- [TIPS_AND_TRICKS.md](TIPS_AND_TRICKS.md) — practical recipes

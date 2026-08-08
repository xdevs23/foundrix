# Agent Guide

Conventions and gotchas for working in this repository. Read the linked docs
before making related changes.

## Supporting multiple NixOS releases

Foundrix evaluates against more than one nixpkgs/Home Manager release at a
time. When an option, default, or library function only exists or only changed
in the newer release, guard it on `lib.versionAtLeast lib.version "<threshold>"`
so the module still evaluates on the older release. Pin legacy values to
silence state-version-gated warnings without changing behavior.

See [docs/release-compat.md](docs/release-compat.md) for the idiom, when to use
it (and when not to), and how to remove the guards once the older release
reaches EOL.

## Other references

- [docs/traits.md](docs/traits.md) — cross-module capability announcements
- [docs/var-luks.md](docs/var-luks.md) — encrypted /var (LUKS2) with automatic migration
- [docs/backup.md](docs/backup.md) — snapshot/replicate a subvolume to pluggable destinations
- [docs/images.md](docs/images.md) — image build/output conventions
- [TIPS_AND_TRICKS.md](TIPS_AND_TRICKS.md) — practical recipes

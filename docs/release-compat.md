# Release Compatibility

Foundrix supports two releases:

- NixOS 26.05, the stable release. The `nixpkgs-stable` flake input tracks it.
- nixos-unstable, which the `nixpkgs` flake input tracks.

Every module evaluates on both. No code, version check, fallback or comment is
kept or added for any other release.

Home Manager follows the same split: `release-26.05` goes with NixOS 26.05 and
`master` goes with nixos-unstable, so one version check covers NixOS and Home
Manager options alike.

## The version check

When an option, default or library function only exists or only changed on
nixos-unstable, a module branches on `lib.version`:

```nix
lib.versionAtLeast lib.version "26.10"
```

`lib.version` is the release string of the nixpkgs in use:

| Release        | Source          | `lib.version`             |
|----------------|-----------------|---------------------------|
| NixOS 26.05    | any             | `26.05.<date>.<rev>`      |
| nixos-unstable | flake           | `26.11.<date>.<rev>`      |
| nixos-unstable | channel         | `26.11pre<number>.<rev>`  |
| nixos-unstable | plain checkout  | `26.11pre-git`            |

nixos-unstable reports the number of the next release, 26.11. Nix compares a
`pre` suffix lower than the bare number, so `26.11pre-git` is lower than
`26.11` and a check against `"26.11"` is false on a channel or a plain
checkout. The threshold is therefore the number one minor below the next
release, `"26.10"`. It is true on every form of nixos-unstable and false on
NixOS 26.05.

## When a check is needed

A check is needed whenever a change would break evaluation on NixOS 26.05.
Three shapes recur.

### 1. An option only exists on nixos-unstable

Setting an unknown option is an evaluation error on NixOS 26.05, so the option
is merged in conditionally. The repart disk image module does this for the
`enable` option of `image.repart`, which nixos-unstable added and which keeps
the repart module inactive until it is set:

```nix
image.repart = {
  inherit (cfg) name seed;
  split = true;
}
# Since 26.11 the repart module stays inactive until enabled. The option
# does not exist on 26.05.
// lib.optionalAttrs (lib.versionAtLeast lib.version "26.10") {
  enable = true;
};
```

### 2. A module or option was renamed or split

When nixos-unstable moves configuration to a module with a different name, the
shared body is defined once and attached under the right name with `lib.mkIf`:

```nix
let
  settings = { /* configuration shared by both modules */ };
  useNewModule = lib.versionAtLeast lib.version "26.10";
in
{
  programs.new-name = lib.mkIf useNewModule settings;
  programs.old-name = lib.mkIf (!useNewModule) settings;
}
```

### 3. A library function was deprecated

If the replacement exists on NixOS 26.05 as well, the module switches to it
unconditionally, with no check. A check is only needed when the replacement is
absent on NixOS 26.05. Availability is verified against the release branch in
a nixpkgs checkout before deciding, for example with
`git grep -n <function> origin/nixos-26.05`.

## When a check is not needed

A check adds noise, so it is left out when a value is valid on both releases.
The common case is a warning that depends on the state version: setting the
legacy value explicitly silences it without changing behavior.

```nix
# Safe on both releases: the legacy default is identical, the explicit
# assignment just stops the warning introduced in 26.05 from firing.
programs.zsh.dotDir = config.home.homeDirectory;
gtk.gtk4.theme = config.gtk.theme;
```

## Clean-up

When a release leaves the supported list, search for
`lib.versionAtLeast lib.version` and collapse every check that release fails to
its newer branch, removing the `lib.optionalAttrs` or `lib.mkIf` wrapper and
the fallback for the release that left.

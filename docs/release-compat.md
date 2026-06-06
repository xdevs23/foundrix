# Release Compatibility

Foundrix targets more than one NixOS/nixpkgs release at a time. During an
overlap window — for example while both the current stable and the previous
stable are still supported — a module may need to evaluate cleanly on *both*
releases even though an option, default, or library function only exists (or
only changed) in the newer one.

The trick is a single runtime version check against `lib.version`:

```nix
lib.versionAtLeast lib.version "26.04"
```

`lib.version` is the nixpkgs/Home Manager release string (e.g. `"25.11..."`
or `"26.05..."`), so this predicate is `true` on the newer release and
`false` on the older one. Use the *lowest* version that already contains the
change as the threshold (the `.04` patchline conventionally lands before the
`.05` tagged release), and branch on it.

## When you need it

Reach for a guard whenever a change would break evaluation on the older
release. Three recurring shapes:

### 1. An option only exists on the newer release

Setting an unknown option is an evaluation error on the old release, so merge
it conditionally:

```nix
wayland.windowManager.hyprland = {
  enable = true;
  # ...
}
# configType does not exist before 26.05; guard it to keep 25.11 evaluating.
// lib.optionalAttrs (lib.versionAtLeast lib.version "26.04") {
  configType = "hyprlang";
};
```

### 2. A module/option was renamed or split

When the newer release moves configuration to a different module, define the
shared body once and attach it under the right name with `lib.mkIf`:

```nix
let
  settings = { /* package-agnostic config */ };
  useNewModule = lib.versionAtLeast lib.version "26.04";
in
{
  programs.vscodium = lib.mkIf useNewModule settings;
  programs.vscode = lib.mkIf (!useNewModule) (settings // { package = pkgs.vscodium; });
}
```

### 3. A library function was deprecated

If the replacement exists on *both* releases, just switch unconditionally — no
guard needed. Only guard when the replacement is absent on the older release.
Always verify availability against the actual release branch before deciding
(e.g. `git show origin/nixos-25.11:lib/cli.nix`).

## When you *don't* need it

A guard adds noise, so skip it when a value is valid on both releases — most
commonly when silencing a state-version-gated default warning by pinning the
legacy value:

```nix
# Safe on both releases: the legacy default is identical, the explicit
# assignment just stops the 26.05 warning from firing.
programs.zsh.dotDir = config.home.homeDirectory;
gtk.gtk4.theme = config.gtk.theme;
```

## Cleanup

These guards are temporary. When the older release reaches EOL and support is
dropped, grep for `lib.versionAtLeast lib.version` and collapse each guard to
its newer-release branch — removing the `lib.optionalAttrs`/`lib.mkIf`
wrappers and any old-release fallback.

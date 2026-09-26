# Lua configuration for the foundrix Hyprland module

The foundrix Hyprland desktop module takes Hyprland 0.56.2 from nixpkgs-unstable, renders its configuration in Hyprland's Lua format, and gives its options a structured shape for that format. The module's own bindings, the idle daemon's wake command and the hypr-workspaced daemon send their Hyprland commands in the Lua request forms. The Quickshell side and the desktop's own configuration belong to the nixos-desktop unit.

## Requirements

**migrate-to-lua**: The Hyprland configuration moves to Hyprland's Lua format.

**update-latest**: Hyprland and Quickshell move to their latest versions, and everything that needs it is migrated.

**changelogs-checked**: What needs migrating is taken from the Hyprland and Quickshell changelogs between the current and the target versions.

**structured-options**: The foundrix Hyprland module's options that held hyprlang text become structured records for the Lua format.

**whole-migration**: Structured records also for window, layer and workspace rules and submaps (the desktop's rules leave Lua text), native Lua functions for the zoom and cursor-nudge bindings, and hypr-workspaced gets its own Lua request module instead of pushing Lua text through the crate's generic dispatcher.

**intended-shape**: Each part uses the mechanism Hyprland's Lua format and the Nix module system provide for the job, with no compensation layer, compatibility shim or workaround around the old format.

**hyprland-from-nixpkgs**: Hyprland 0.56.2 and its desktop portal come from nixpkgs-unstable instead of the Hyprland flake.

**commands-follow**: Every command sent to Hyprland as a dispatch or keyword request moves to the Lua forms. Other hyprctl requests, such as kill, notify and cursorpos, stay as they are.

**package-source**: The module takes Hyprland and its desktop portal from nixpkgs-unstable: the NixOS Hyprland program, the Home Manager Hyprland module and the session manager's compositor entry use nixpkgs-unstable's Hyprland package and its portal package, and the module neither reads nor checks for a Hyprland flake input any more. Nothing replaces that check. This rules out keeping the flake input.

**lua-config-type**: Home Manager's Hyprland configuration type is set to Lua inside the existing release check, and the check's comment describes that value.

**option-shape**: The module's options take this shape.
- monitors is an ordered list of monitor records. A record requires the output selector output and takes
  any further field of Hyprland's monitor function as a free-form attribute. Each record becomes one
  monitor rule in list order, followed by the module's existing catch-all rule for unlisted monitors.
- additionalBinds replaces the three lists of plain, repeating and mouse bindings. A binding record has
  the fields keys, action and flags. keys is the Hyprland Lua key string. action is required and is a
  tagged union with exactly one of two alternatives: exec, a shell command the module runs through
  Hyprland's command dispatcher with the text quoted as a Lua string, or lua, a Lua expression that
  evaluates to a dispatcher or a function. flags is a free-form attribute set of boolean, integer or
  string values passed unchanged as the options of Hyprland's bind function; it defaults to empty.
  Mouse bindings need no flag: the drag and resize dispatchers carry their mouse behaviour.
- additionalWindowRules, additionalLayerRules and additionalWorkspaceRules are lists of free-form records
  in the shape of the matching Hyprland Lua rule function. Each record becomes one rule after the
  module's own rules, in list order.
- submaps maps a submap name to a list of binding records. Each entry becomes one submap definition
  whose bindings use the binding record type; entering a submap is an ordinary binding whose lua action
  is the submap dispatcher.
- extraConfig holds Lua text, appended after the generated configuration, for anything the structured
  options do not cover.
- menu is a read-only option holding the application menu command the old configuration kept in a
  hyprlang variable, so consumers can build commands with it.
- mainMod holds Hyprland Lua modifier names joined with " + " (default SUPER). The module and its
  consumers build key strings by joining it with the other keys in Nix; the module defines no Lua
  variable for it.
The three old binding options additionalBind, additionalBinde and additionalBindm are declared removed
with the module system's removed-option mechanism, whose message points to additionalBinds. The module
declares its own bindings, window rules and layer rules with the same record types and renders its own
entries and the extra ones through one rendering path per kind. The other options keep their names and
meaning. Using the tagged union type rules out two optional fields checked by an assertion.

**start-up-once**: The module's start-up commands, its two clipboard history watchers and the execOnce entries, run in one handler of the hyprland.start event through Hyprland's command function, so reloading the configuration does not start them again. This rules out calling the command function at the top level of the configuration.

**native-zoom-binds**: The cursor zoom bindings are Lua functions inside Hyprland. Zooming in and out reads the current cursor.zoom_factor with Hyprland's configuration getter, multiplies it by 1.1 or 0.9 and sets the result with Hyprland's configuration setter; the reset bindings set it to 1. Keys and the repeating behaviour of each zoom binding stay as they are, and the result is not limited to a range, as before. This rules out shell pipelines that start processes per key press.

**idle-wake-command**: The idle daemon's after-sleep command is exactly: hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'

**workspaced-requests**: hypr-workspaced sends its commands to Hyprland in the Lua forms, through one module of its own that
writes one request to Hyprland's command socket, reads the whole answer, and treats any answer other
than ok as an error carrying the request and the answer. Dispatches go out as dispatch requests and
workspace rules as eval requests. The module builds the Lua text from typed values, one variant per
kind of request, and quotes every string value as a Lua string literal through one function. The forms:
- focus a workspace: hl.dsp.focus({ workspace = "<id>" })
- move a window to a workspace without following it:
  hl.dsp.window.move({ window = "address:<address>", workspace = "<id>", follow = false })
- move a window to a workspace and follow it:
  hl.dsp.window.move({ window = "address:<address>", workspace = "<id>" })
- move the active window to a workspace and follow it: hl.dsp.window.move({ workspace = "<id>" })
- move a workspace to a monitor: hl.dsp.workspace.move({ workspace = "<id>", monitor = "<name>" })
- focus a window: hl.dsp.focus({ window = "address:<address>" })
- workspace rule: hl.workspace_rule({ workspace = "<id>", monitor = "<name>", persistent = true, default = <true or false> })
The socket is found by the crate's rule: the directory named by XDG_RUNTIME_DIR, else /run/user/ with the
value of the UID environment variable, then hypr/<HYPRLAND_INSTANCE_SIGNATURE>/.socket.sock; with neither
variable set the request fails with an error. The crate stays in use for reading Hyprland's state and
for its event stream; its dispatch and keyword interfaces are no longer used. This rules out sending Lua
text through the crate's custom dispatcher variant.

**lua-only**: No part of this unit keeps a hyprlang path next to the Lua one: no second rendering of the configuration and no old-format request kept as a fallback.

## Boundaries

**no-side-work**: Nothing outside the update and the migration changes. Settings, bindings and behaviour keep their current values unless the Lua format or the new package source forces a change. No unrelated clean-up, refactoring or feature work is part of the unit.

**foundrix-in-scope**: The changes of this unit are made in the foundrix repository.

**no-work-for-25-11**: No work is done for NixOS 25.11. The existing release check around Home Manager's configuration type stays as it is apart from its value, and no release compatibility code is added, changed or removed. The module is not required to evaluate on 25.11.

**desktop-unit-part**: The Quickshell update, the Quickshell shells' Hyprland requests, the removal of the Hyprland flake input and the desktop's own consumer configuration are the nixos-desktop unit's part of the request. This unit covers foundrix: the Hyprland module and hypr-workspaced.

**current-version**: The desktop runs Hyprland v0.55.2 today: its flake locks the commit tagged v0.55.2.

**latest-release**: The latest Hyprland release is v0.56.2.

**hyprland-changelog**: Between v0.55.2 and v0.56.2 the Hyprland changelogs hold these entries that concern this setup:
- 0.55.0 made the Lua configuration the default;
- 0.55.3 fixed a submap whose entering binding is the same key as a binding inside it;
- 0.56.0 lists no breaking changes;
- 0.56.1 added a deprecation notice for hyprlang configurations.
The release notes of 0.55.4 and 0.56.2 hold bug fixes only.

**nixpkgs-unstable-locked**: The nixpkgs-unstable source in the local store is the one nixos-desktop locks: its content hash equals the locked hash.

**nixpkgs-unstable-hyprland**: That nixpkgs-unstable packages Hyprland 0.56.2 from the v0.56.2 tag, relaxes the glaze version check the release refuses to build without, and its Hyprland package is the store path the checks run.

**nixpkgs-unstable-portal**: The same nixpkgs-unstable packages the Hyprland desktop portal at version 1.4.1.

**package-cached**: That Hyprland package is in the public binary cache, so it needs no local build.

**package-programs**: That Hyprland package ships the Hyprland, hyprctl and start-hyprland programs the desktop starts.

**system-mesa**: The Mesa build the checks load is the one nixos-26.05, as nixos-desktop locks it, provides.

**lua-shapes-work**: In a recorded run, that Hyprland package ran headless with that Mesa build, each Lua request form the units use took effect, and the old dispatcher and keyword forms were refused.

**keyword-refused**: With a Lua configuration, Hyprland 0.56.2 refuses the keyword request.

**dispatch-is-lua**: With a Lua configuration, Hyprland 0.56.2 runs the text after a dispatch request as the Lua expression given to its dispatch function, so old dispatcher text is a Lua error.

**hyprctl-exit-status**: hyprctl exits with status 7 only when Hyprland's answer starts with "error:", so a refused keyword request, whose answer does not, exits with status 0, and so does an eval request whose answer carries only warnings.

**other-hyprctl-requests**: Hyprland 0.56.2 still serves the kill, notify and cursorpos requests under a Lua configuration; only keyword refuses non-legacy parsers and only dispatch changes its meaning.

**module-uses-flake-input**: The module takes Hyprland, its portal and the start-hyprland program from the Hyprland flake input today, and wraps its whole configuration in a check that the input exists, which it skips when foundrix evaluates modules without their inputs.

**docs-output-broken**: foundrix's own option documentation output, which evaluates every module without its inputs, already fails to evaluate at the base commit for a reason unrelated to Hyprland.

**hyprland-senders**: In foundrix, the Hyprland module's bindings and idle daemon and the hypr-workspaced daemon are the places that send commands to Hyprland.

**home-manager-renders-lua**: Home Manager 26.05's Hyprland module offers a Lua configuration type. It renders each settings attribute as a call of the Hyprland Lua function of that name, and puts start-up commands into a handler of the hyprland.start event.

**reload-reruns-config**: Hyprland 0.56.2 emits its start event once per session, while every reload loads the whole Lua configuration file again.

**tagged-union-type**: The module system of nixpkgs 26.05 has a tagged union option type that accepts exactly one of several named alternatives, and a way to declare a removed option with an explanation.

**no-mouse-flag**: Hyprland 0.56.2's Lua bind function reads no mouse option; the drag and resize dispatchers give a binding its hold-to-move behaviour themselves.

**bind-options**: The options Hyprland 0.56.2's Lua bind function reads are repeating, locked, release, non_consuming, auto_consuming, transparent, ignore_mods, dont_inhibit, long_press, submap_universal, click, drag, description, device and allow_input_capture.

**zoom-baseline**: In a recorded run against the current configuration, one zoom-in press multiplies the zoom factor by 1.1, one zoom-out press by 0.9, and a reset press sets it to 1.

**zoom-range-accepted**: In a recorded run, Hyprland's Lua configuration setter stored zoom factors of 0.5 and 11 and the product of a bind at factor 1 times 0.9 without an error, as the old keyword request did.

**crate-speaks-hyprlang**: hypr-workspaced uses the hyprland Rust crate 0.4.0-beta.3, the crate's newest release, which sends runtime settings as keyword requests and dispatches as old dispatcher text, and whose socket writer and socket lookup are private to the crate. The lookup takes XDG_RUNTIME_DIR, else /run/user/ with the value of the UID environment variable, and fails when neither is set.

**crate-reads-still-work**: In recorded runs on Hyprland 0.56.2, the current hypr-workspaced passes the end-to-end check with a hyprlang configuration, so the crate's state queries and event stream work with 0.56.2, and fails it under a Lua configuration.

**workspace-rule-replaces**: A Lua workspace rule for a workspace that already has one replaces that rule.

**readme-crate-dispatch**: The hypr-workspaced read-me describes the crate's dispatch interface as the daemon's way of commanding Hyprland in its usage example, its architecture diagram, its dependency table and its notes on the crate.

**fixture-harness**: The checks of this unit render the module through a fixture consumer that sets every option shape, inside an otherwise complete desktop system, with foundrix taken from the tree under check.

## Rejected alternatives

**separate-nixpkgs-for-hyprland**: Keep the Hyprland flake and make 0.56.2 build by giving it a separately locked nixpkgs input declared in the consumer's flake.
Reason: It adds a second nixpkgs input to the consumer's flake only to work around the release's own lock.

**flake-at-bump-commit**: Keep the Hyprland flake input, locked to the commit that bumped the version to 0.56.2, whose own lock still builds.
Reason: The nixpkgs-unstable package was chosen as the source.

**raw-home-manager-shape**: Pass the module's options straight through to Home Manager's Lua settings, with consumers writing Home Manager's argument lists and inline Lua values themselves.
Reason: Structured records were chosen for the module's options.

## Acceptance criteria

1. **fixture-config-loads**: For the fixture consumer, which sets every option shape (two monitor records with extra fields; bindings with an exec action, with a lua action and the repeating flag, and with the drag dispatcher on a mouse button; the menu option inside a command; a start-up command; a window rule, a layer rule and a workspace rule; a submap with its entering binding; and Lua extra configuration), the generated configuration passes Hyprland 0.56.2's configuration check, and that system's Hyprland package started headless with it reports no configuration errors and a Lua configuration provider.
2. **inventory-preserved**: Item by item, every entry of the module's previous hyprlang settings has a Lua equivalent with the same effect, and nothing was added: the four environment variables, the catch-all monitor rule, the two clipboard watchers and the execOnce entries in the hyprland.start handler, every input, cursor, general, decoration, animation, dwindle, render and miscellaneous value, the bezier curve and the seven animations, the seven gestures, the two layer rules, the four window rules, and every binding with its keys, action and repeating behaviour, including the numbered workspace bindings, the horizontal-scroll workspace bindings, the duplicated keypad-centre click binding, the hyprctl kill binding and the two mouse bindings on the drag and resize dispatchers. Integer options get integer values of the same meaning.
3. **option-shape-holds**: The module's options have the shape the option-shape requirement describes; the fixture consumer's window, layer and workspace rules and its submap appear in the generated configuration as the matching Lua rule calls and submap definition; setting any of the three old binding options fails evaluation with a message that names additionalBinds; a binding record whose action is empty or has both alternatives fails evaluation with an option type error; and a binding record without an action fails evaluation because the required action has no value.
4. **zoom-binds-hold**: Pressed on a real keyboard in a headless Hyprland started with the fixture configuration, the zoom keys change the zoom factor from 1 to 1.1, then to 1.21, then zoom out to 1.089, and the reset keys set it to 1; the module no longer contains a keyword, getoption or old dispatcher request.
5. **idle-wake-holds**: The generated idle daemon configuration's after-sleep command is exactly the form the idle-wake-command requirement gives.
6. **package-source-holds**: In the fixture system, the NixOS Hyprland program, the Home Manager Hyprland module and the session manager's compositor entry use nixpkgs-unstable's Hyprland 0.56.2 and its portal package, and the module no longer mentions a Hyprland flake input.
7. **release-check-holds**: The release check around the configuration type is unchanged apart from the value, which is now the Lua type, and its comment describes that value correctly.
8. **workspaced-requests-hold**: hypr-workspaced no longer uses the hyprland crate's dispatch or keyword interfaces, every command it sends to Hyprland goes through its request module in exactly the forms the workspaced-requests requirement lists, unit tests assert each form as an exact string including the quoting of a string value that holds a double quote, a backslash and a line break, and the package builds with its tests passing.
9. **workspaced-end-to-end**: Run against a headless Hyprland with a Lua configuration, the hypr-workspaced daemon sets one persistent workspace rule per virtual workspace, switches workspaces, moves the active window with focus following, gathers a window from a workspace no monitor shows, steps to the next and previous workspace, and assigns again without duplicating rules; every command exits successfully and the daemon logs no error.
10. **workspaced-readme-current**: Nothing in the hypr-workspaced read-me describes the crate's dispatch or keyword interface as the daemon's way of commanding Hyprland: its usage example matches the Lua configuration and the foundrix module's options, its architecture diagram, dependency table and notes on the crate say that dispatches and workspace rules go through the daemon's own Lua request module while the crate handles state queries and events.

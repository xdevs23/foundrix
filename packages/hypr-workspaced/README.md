# hypr-workspaced

A Rust daemon for managing synchronized virtual workspaces across multiple Hyprland monitors.

## The Problem

Hyprland assigns workspaces to individual monitors. With multiple monitors, pressing `Super+3` only switches the *focused* monitor to workspace 3, leaving other monitors unchanged. This creates a fragmented experience where you can't think of "workspace 3" as a unified context across all displays.

**Before:** Each monitor has independent workspaces. Super+3 on monitor A does nothing to monitor B.

**After:** All monitors switch together. Super+3 puts monitor 0 on workspace 3, monitor 1 on workspace 13, monitor 2 on workspace 23, etc. — a unified "virtual workspace 3" across all displays.

## How It Works

The daemon implements a **virtual workspace** abstraction:

| Virtual WS | Monitor 0 | Monitor 1 | Monitor 2 |
|------------|-----------|-----------|-----------|
| 1          | 1         | 11        | 21        |
| 2          | 2         | 12        | 22        |
| 3          | 3         | 13        | 23        |
| ...        | ...       | ...       | ...       |
| 9          | 9         | 19        | 29        |

Formula: `workspace_id = (slot * 10) + virtual_workspace` (slot 0 uses 1-9 directly). Each monitor
gets a slot that stays: the daemon records monitors by description, which contains the serial
number, or by name when a monitor has no description, such as a headless output, in
`$XDG_STATE_HOME/hypr-workspaced/monitors`.

## Features

- **Synchronized switching**: All monitors switch to the same virtual workspace
- **Monitor hotplug**: Automatically reassigns workspaces when monitors are added/removed
- **Fast IPC**: Daemon stays resident; keybinds just send commands via Unix socket
- **Collapse**: Pull windows from the same virtual workspace on other monitors to the current one
- **Pinned windows**: Pin windows (by class, title, etc.) so they follow workspace switches

## Installation

### NixOS with the foundrix Hyprland module

The foundrix Hyprland module installs the daemon and runs it as a systemd user service. After the
daemon starts, the service runs `assign` and one `pin` per entry of `hyprWorkspacedPins`. The module
binds `mainMod + 1-9` to `switch`, `mainMod + SHIFT + 1-9` to `move`, `mainMod + C` and
`mainMod + SHIFT + C` to `collapse invisible` and `collapse all`, `mainMod + I` and
`mainMod + SHIFT + I` to `swap next` and `swap prev`, and `mainMod` with the horizontal scroll
buttons to `prev` and `next`.

`hyprWorkspacedOnReconnectRestart` names a systemd user service that the daemon restarts when its
event connection to Hyprland closes or fails and it has subscribed again, for example after
Hyprland dropped it for falling 64 events behind
(<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/ipc/s2/Unix.cpp>, `MAX_QUEUED_EVENTS`,
checked 2026-11-08). A program such as a top bar that reads the events of Hyprland as well usually
lost its connection at the same moment.

```nix
foundrix.components.desktop-environments.hyprland = {
  # Pin windows to follow workspace switches
  hyprWorkspacedPins = [ "class:Mattermost" ];
  hyprWorkspacedOnReconnectRestart = "quickshell-topbar.service";
  additionalBinds = [
    {
      keys = "SUPER + N";
      action.exec = "hypr-workspaced next";
    }
  ];
};
```

### Other Hyprland Lua configurations

```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("hypr-workspaced daemon")
end)

hl.bind("SUPER + 1", hl.dsp.exec_cmd("hypr-workspaced switch 1"))
hl.bind("SUPER + 2", hl.dsp.exec_cmd("hypr-workspaced switch 2"))
-- ... etc
hl.bind("SUPER + SHIFT + 1", hl.dsp.exec_cmd("hypr-workspaced move 1"))
hl.bind("SUPER + SHIFT + 2", hl.dsp.exec_cmd("hypr-workspaced move 2"))
-- ... etc
hl.bind("SUPER + C", hl.dsp.exec_cmd("hypr-workspaced collapse invisible"))
```

Pins are added with `hypr-workspaced pin <pattern>` once the daemon runs.

### Manual

```bash
cargo build --release
./target/release/hypr-workspaced daemon &
```

## Commands

```bash
hypr-workspaced daemon              # Start the daemon (foreground, from a service or hyprland.start)
hypr-workspaced switch <1-9>        # Switch all monitors to virtual workspace
hypr-workspaced move <1-9>          # Move active window to virtual workspace, then switch
hypr-workspaced next                # Switch to next virtual workspace (wraps 9 -> 1)
hypr-workspaced prev                # Switch to previous virtual workspace (wraps 1 -> 9)
hypr-workspaced swap <next|prev>    # Swap windows with the neighboring monitor, by position
hypr-workspaced collapse all        # Move all windows from same virtual WS to current monitor
hypr-workspaced collapse invisible  # Move windows on workspaces no monitor shows to current one
hypr-workspaced assign              # Manually reassign workspaces (usually automatic)
hypr-workspaced pin <pattern>       # Pin windows matching pattern to follow workspace switches
hypr-workspaced unpin <pattern>     # Remove a pinned pattern
hypr-workspaced pins                # List all pinned patterns
hypr-workspaced debug <on|off>      # Switch debug logging of the daemon
```

`daemon` takes `--on-hypr-ipc-reconnect-restart <service>`, the systemd user service to restart
after the event connection to Hyprland was lost and subscribed again (see the NixOS installation
above).

### Window Patterns

The `pin` and `unpin` commands accept patterns using Hyprland's window identifier syntax:

| Pattern | Description | Example |
|---------|-------------|---------|
| `class:<string>` | Match window class (substring) | `class:Firefox` |
| `title:<string>` | Match window title (substring) | `title:YouTube` |
| `pid:<number>` | Match process ID | `pid:1234` |
| `address:<hex>` | Match window address | `address:0x12345678` |
| `floating:<bool>` | Match floating state | `floating:true` |
| `fullscreen:<bool>` | Match fullscreen state | `fullscreen:false` |

Pinned windows will automatically move to the target virtual workspace when you switch workspaces. They stay on their current monitor — only the workspace changes.

## IPC Socket

The daemon listens on a Unix socket for commands from the CLI.

**Location:** `$XDG_RUNTIME_DIR/hypr-workspaced.sock`. The daemon and the CLI fail with an error
when `XDG_RUNTIME_DIR` is not set.

**Protocol:** One command line per connection. The daemon writes its answer and closes the
connection, so the data of `pins` can span several lines.

| Request | Response |
|---------|----------|
| `switch 3\n` | `ok\n` or `error: message\n` |
| `move 5\n` | `ok\n` or `error: message\n` |
| `next\n` | `ok\n` or `error: message\n` |
| `prev\n` | `ok\n` or `error: message\n` |
| `swap next\n` | `ok\n` or `error: message\n` |
| `collapse all\n` | `ok\n` or `error: message\n` |
| `collapse invisible\n` | `ok\n` or `error: message\n` |
| `assign\n` | `ok\n` or `error: message\n` |
| `pin class:Firefox\n` | `ok\n` or `error: message\n` |
| `unpin class:Firefox\n` | `ok\n` or `error: message\n` |
| `pins\n` | `data: class:Firefox\nclass:Mattermost\n` |
| `debug on\n` | `ok\n` or `error: message\n` |

You can interact directly via socat if needed:

```bash
echo "switch 3" | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr-workspaced.sock
```

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                      hypr-workspaced daemon                    │
│                                                                │
│  ┌─────────────────┐    ┌──────────────────┐    ┌───────────┐  │
│  │  event reader   │    │ WorkspaceManager │    │  server   │  │
│  │                 │    │                  │    │           │  │
│  │ - hyproxide     │    │ - assign         │    │ - socket  │  │
│  │   events        │    │ - switch(n)      │    │ - Command │  │
│  │ - latest change │    │ - move_to(n)     │    │   parsing │  │
│  │   per kind      │    │                  │    │           │  │
│  └────────┬────────┘    └────────┬─────────┘    └─────┬─────┘  │
│           │                      ▼                    │        │
│           │             ┌──────────────────┐          │        │
│           │             │    hyproxide     │          │        │
│           │             │ - dispatchers    │          │        │
│           │             │ - workspace rule │          │        │
│           │             │ - JSON queries   │          │        │
│           │             └──────────────────┘          │        │
│           └──────────────────────┬────────────────────┘        │
│                                  ▼                             │
│                          ┌──────────────┐                      │
│                          │ tokio select │                      │
│                          │  event loop  │                      │
│                          └──────────────┘                      │
└────────────────────────────────────────────────────────────────┘
```

The daemon talks to Hyprland only through [hyproxide](../hyproxide), the IPC library for
Hyprland 0.57 in this repository: its events, its queries (monitors, windows, workspaces, the
active workspace and the cursor position), its dispatchers (workspace focus, window and workspace
moves) and its typed workspace rule.

The event reader runs in a task of its own. Hyprland drops a program that falls 64 events behind
(<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/ipc/s2/Unix.cpp>, `MAX_QUEUED_EVENTS`,
checked 2026-11-08), so the reader never waits for the daemon: it keeps only the latest change of each kind in a watch
channel (the numbered workspace focused last, a change of monitors or configuration, a new
subscription) and reads on, while the event loop acts on those changes and on the commands of the
CLI. Events the daemon does not act on, special and named workspaces, windows with commas in their
titles and events newer than hyproxide included, are read and skipped. An event the daemon acts on
whose data hyproxide cannot read is logged as a warning, and a change of monitors among them still
makes the daemon reassign the workspaces.

When the event socket closes or fails, the reader subscribes again, the daemon reassigns the
workspaces, as the events in between are lost, and restarts the service given to
`--on-hypr-ipc-reconnect-restart`. When Hyprland cannot be reached anymore, the daemon exits with
an error.

---

# Development

## Dependencies

| Crate | Purpose |
|-------|---------|
| `hyproxide` | Events, queries and commands of Hyprland 0.57 |
| `tokio` | Async runtime |
| `clap` | CLI argument parsing |
| `thiserror` | Error type derivation |
| `tracing` | Structured logging |
| `tracing-subscriber` | Log output formatting |
| `sd-notify` | Readiness for a systemd service of type notify |
| `zbus` | Restart a systemd user service over D-Bus |
| `serde` | The job mode and job result of systemd as typed values on D-Bus |

See `Cargo.toml` for the versions and the minimum Rust version. The Nix package builds from this
directory and `packages/hyproxide`, with the one `Cargo.lock` of this directory.

## Checks

- `cargo test` runs the unit tests, among them one that feeds a fake event socket and closes it,
  and the tests of the plans of `swap`, `collapse` and the pinned windows on answers recorded from
  Hyprland 0.57.1 in `testdata/hyprland-answers`.
- The flake checks `hypr-workspaced-clippy` and `hypr-workspaced-fmt` run clippy, with pedantic
  lints denied, and `cargo fmt --check`.
- The flake check `hypr-workspaced-end-to-end` runs `tests/end_to_end.rs` in a NixOS VM against a
  headless Hyprland with two outputs, started by the crate `hyproxide-testing` in
  `packages/hyproxide/testing`: it opens and closes a special workspace and a window with a comma
  in its title, switches workspaces on both outputs, makes Hyprland drop the event connection of
  the stopped daemon, sends twice as many events while the running daemon is busy, and checks that
  the daemon keeps the outputs in step and restarts a stand-in service only after the drop.

## Best Practices

### Keep the Daemon Resident

Spawning a process per keybind adds latency. A resident daemon with IPC is much faster:

- **Bash script per keybind:** ~50-100ms (fork + shell + hyprctl calls)
- **Daemon + IPC:** ~1-5ms (socket write + existing process)

### Use Batch Operations Sparingly

`hyprctl --batch` can help, but the daemon makes individual async calls through hyproxide, one connection per request, each waiting until Hyprland accepts it.

### Handle Special Workspaces

Since Hyprland 0.57 only numbered workspaces have an id. Special and named workspaces are known by
their address, which hyproxide reads into `WorkspaceAddress`. The daemon acts only on numbered
workspaces, and leaves windows on special and named workspaces where they are.

### Monitor IDs vs Monitor Names

Monitor IDs are assigned by Hyprland at runtime and can change on hotplug. Monitor names (like `DP-1`, `eDP-1`) are stable. Use names for workspace rules, IDs for runtime logic.

### Orphan Workspace Cleanup

Hyprland may create orphan workspaces (10, 20, ...) before your daemon starts. Clean them up by moving windows to valid workspaces. Hyprland 0.57 has no workspace 0.

## Debugging

### Check if daemon is running

```bash
pgrep -a hypr-workspaced
ls -la $XDG_RUNTIME_DIR/hypr-workspaced.sock
```

### View daemon logs

Start in foreground:

```bash
RUST_LOG=debug hypr-workspaced daemon
```

### Test IPC manually

```bash
echo "switch 3" | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr-workspaced.sock
```

### Query Hyprland state

```bash
hyprctl monitors -j | jq .
hyprctl workspaces -j | jq .
hyprctl clients -j | jq .
```

## Project Structure

- `main.rs`: the clap subcommands that start daemon mode or client mode, and the log filter.
- `daemon.rs`: the event loop, with one method of `Daemon` per event or command it handles.
- `server.rs`: the socket of the daemon, one command and one answer per connection.
- `systemd.rs`: the typed D-Bus calls to the systemd user manager, in the library target, which the
  end-to-end test uses as well.
- `events.rs`: subscribes to the events of Hyprland through hyproxide and keeps the latest change
  of each kind the daemon acts on.
- `client.rs`: connects to the daemon, sends one command and prints the answer.
- `workspace.rs`: `WorkspaceManager`, which queries Hyprland, runs the commands and dispatches
  their requests through hyproxide.
- `plan.rs`: the window moves of `swap`, `collapse` and the pinned windows, planned from the
  answers of Hyprland.
- `layout.rs`: the slot of each connected monitor.
- `monitor_registry.rs`: the permanent slot of each monitor ever seen, in the state directory.
- `virtual_workspace.rs`: virtual workspaces, monitor slots and the Hyprland workspace ids made of
  both.
- `window.rs`: `WindowPattern`, the patterns of pinned windows.
- `ipc.rs`: the `Command` and `Response` enums, their text form and the path of the socket.
- `error.rs`: the error enum with one variant per operation that fails, and the failed steps of a
  workspace sync.

## License

GPL-3.0-only

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

Formula: `workspace_id = (monitor_id * 10) + virtual_workspace` (monitor 0 uses 1-9 directly)

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
hypr-workspaced collapse            # Move all windows from same virtual WS to current monitor
hypr-workspaced assign              # Manually reassign workspaces (usually automatic)
hypr-workspaced pin <pattern>       # Pin windows matching pattern to follow workspace switches
hypr-workspaced unpin <pattern>     # Remove a pinned pattern
hypr-workspaced pins                # List all pinned patterns
```

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

**Location:** `$XDG_RUNTIME_DIR/hypr-workspaced.sock`

**Protocol:** Line-based text protocol.

| Request | Response |
|---------|----------|
| `switch 3\n` | `ok\n` or `error: message\n` |
| `move 5\n` | `ok\n` or `error: message\n` |
| `next\n` | `ok\n` or `error: message\n` |
| `prev\n` | `ok\n` or `error: message\n` |
| `collapse\n` | `ok\n` or `error: message\n` |
| `assign\n` | `ok\n` or `error: message\n` |
| `pin class:Firefox\n` | `ok\n` or `error: message\n` |
| `unpin class:Firefox\n` | `ok\n` or `error: message\n` |
| `pins\n` | `data: class:Firefox\nclass:Mattermost\n` |

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
│  │   hyprland-rs   │    │ WorkspaceManager │    │ IpcServer │  │
│  │                 │───►│                  │◄──►│           │  │
│  │ - EventListener │    │ - assign_all()   │    │ - socket  │  │
│  │ - data types    │    │ - switch(n)      │    │ - Command │  │
│  │                 │    │ - move_to(n)     │    │   parsing │  │
│  └────────┬────────┘    └────────┬─────────┘    └─────┬─────┘  │
│           │                      ▼                    │        │
│           │             ┌──────────────────┐          │        │
│           │             │  Request module  │          │        │
│           │             │ - Lua commands   │          │        │
│           │             │ - JSON queries   │          │        │
│           │             │ - waits for room │          │        │
│           │             │   in the queue   │          │        │
│           │             └──────────────────┘          │        │
│           └──────────────────────┬────────────────────┘        │
│                                  ▼                             │
│                          ┌──────────────┐                      │
│                          │ tokio select │                      │
│                          │  event loop  │                      │
│                          └──────────────┘                      │
└────────────────────────────────────────────────────────────────┘
```

hyprland-rs delivers Hyprland's events and provides the data types of its state. Every request the
daemon sends to Hyprland goes through the daemon's own request module: the commands (workspace
focus, window and workspace moves, and workspace rules) and the state queries (monitors, windows,
workspaces, the active workspace and the cursor position).

Hyprland queues at most 10 connections on its command socket. Other clients, such as bars and lock
screens, can fill that queue for a moment, and a connect that does not wait then fails with
`EAGAIN`. The request module connects with a blocking connect whose send timeout is 5 s, the time
Hyprland itself waits for the request of a client it has accepted, so the kernel holds the connect
until Hyprland accepts it. Only when the queue stays full for the whole 5 s does the request fail,
with an error that says so.

---

# Development

## Dependencies

| Crate | Version | Purpose |
|-------|---------|---------|
| `hyprland` | 0.4.0-beta.3 | Hyprland events and state data types |
| `socket2` | 0.6.1 | Connect to Hyprland's command socket with a send timeout |
| `serde_json` | 1.0.149 | Deserialize Hyprland's JSON answers |
| `tokio` | 1.49 | Async runtime |
| `clap` | 4.5 | CLI argument parsing |
| `thiserror` | 2.0 | Error type derivation |
| `tracing` | 0.1 | Structured logging |
| `tracing-subscriber` | 0.3 | Log output formatting |

## hyprland-rs API Learnings

### Data Types

The hyprland-rs types are not always what you'd expect from the docs:

```rust
// Workspace ID is just i32
pub type WorkspaceId = i32;

// WorkspaceBasic contains id and name
pub struct WorkspaceBasic {
    pub id: WorkspaceId,  // i32
    pub name: String,
}

// Monitor.active_workspace is WorkspaceBasic, not WorkspaceId
pub struct Monitor {
    pub active_workspace: WorkspaceBasic,
    pub id: i128,  // Note: monitor ID is i128!
    pub name: String,
    pub focused: bool,
    // ...
}

// Client.workspace is also WorkspaceBasic
pub struct Client {
    pub workspace: WorkspaceBasic,
    pub address: Address,
    // ...
}
```

### State Queries

The daemon does not use the crate's query functions (`Monitors::get_async` and the like). They
connect to Hyprland's command socket without waiting, so they fail while Hyprland's request queue
is full, and the crate offers no way to change that.

The daemon's query module sends the same requests in their JSON form through the request module
and deserializes the answers with `serde_json` into the crate's data types. It returns plain
`Vec`s:

```rust
let monitors = query::monitors().await?;          // j/monitors all, disabled monitors included
let focused = query::active_monitor().await?;     // the focused entry of that answer
let clients = query::clients().await?;            // j/clients
let workspaces = query::workspaces().await?;      // j/workspaces
let active = query::active_workspace().await?;    // j/activeworkspace
let cursor = query::cursor_position().await?;     // j/cursorpos
```

A monitors answer without a focused entry makes `active_monitor` return an error.

### Commands to Hyprland

The daemon uses neither the crate's `Dispatch` nor its `Keyword` interface. The crate sends
dispatches as old dispatcher text and runtime settings as `keyword` requests. With a Lua
configuration, Hyprland runs the text of a `dispatch` request as the argument of `hl.dispatch(...)`
and refuses `keyword` requests, so both fail.

The daemon's Lua request module has one variant per command. It renders the Lua text from typed
values, quotes every string as a Lua string literal, sends dispatches as `dispatch` requests and
workspace rules as `eval` requests, and treats any answer other than `ok` as an error:

```rust
Request::FocusWorkspace(wsid).send().await?;
// dispatch hl.dsp.focus({ workspace = "13" })

Request::WorkspaceRule { workspace: wsid, monitor: &monitor.name, default: true }.send().await?;
// eval hl.workspace_rule({ workspace = "1", monitor = "DP-1", persistent = true, default = true })
```

### Event Handlers

Event handlers must return `Pin<Box<dyn Future<...>>>`:

```rust
// WRONG
listener.add_monitor_added_handler(move |data| {
    async move { /* ... */ }  // Error: expected Pin<Box<...>>
});

// CORRECT
listener.add_monitor_added_handler(move |data| {
    Box::pin(async move { /* ... */ })
});
```

### Event Data Types

Monitor event data types differ:

```rust
// MonitorAddedEventData has fields: id, name, description
listener.add_monitor_added_handler(move |data| {
    println!("Added: {}", data.name);  // NOT data.monitor_name
});

// MonitorRemovedEventData is just a String (the monitor name)
listener.add_monitor_removed_handler(move |monitor_name| {
    println!("Removed: {monitor_name}");
});
```

### Error Type Location

`HyprError` is in `hyprland::error`, not `hyprland::shared`:

```rust
// WRONG
use hyprland::shared::HyprError;

// CORRECT
use hyprland::error::HyprError;
```

## Best Practices

### Keep the Daemon Resident

Spawning a process per keybind adds latency. A resident daemon with IPC is much faster:

- **Bash script per keybind:** ~50-100ms (fork + shell + hyprctl calls)
- **Daemon + IPC:** ~1-5ms (socket write + existing process)

### Use Batch Operations Sparingly

`hyprctl --batch` can help, but the daemon makes individual async calls through its request module, one connection per request, each waiting for room in Hyprland's request queue.

### Handle Special Workspaces

Special workspaces have negative IDs. Always check:

```rust
fn is_special_workspace(id: WorkspaceId) -> bool {
    id < 0
}
```

### Monitor IDs vs Monitor Names

Monitor IDs are assigned by Hyprland at runtime and can change on hotplug. Monitor names (like `DP-1`, `eDP-1`) are stable. Use names for workspace rules, IDs for runtime logic.

### Orphan Workspace Cleanup

Hyprland may create orphan workspaces (0, 10, 20, ...) before your daemon starts. Clean them up by moving windows to valid workspaces.

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

- Command-line entry: the clap subcommands that start daemon mode or client mode.
- Daemon mode: the event loop, the IPC server and the handling of Hyprland events.
- Client mode: connects to the daemon and sends one command.
- Workspace manager (`WorkspaceManager`): all business logic.
- Window patterns (`WindowPattern`): pattern matching for pinned windows.
- IPC protocol: the `Command` and `Response` enums and the parsing of the protocol.
- Request module (`Request`): the Lua requests sent to Hyprland's command socket, and the one
  connection path to that socket, which waits for room in Hyprland's request queue.
- Query module: Hyprland's state, read with JSON requests through the request module.
- Error types: the daemon's own error types.

## License

GPL-3.0-only

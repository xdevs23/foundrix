use std::collections::HashMap;
use std::num::{NonZeroU8, NonZeroU16};
use std::path::PathBuf;

use hyproxide::Instance;
use hyproxide::address::Address;
use hyproxide::dispatch::window::{self, Movement};
use hyproxide::dispatch::{self, Focus, MonitorSelector, rule, workspace};
use hyproxide::monitor::MonitorId;
use hyproxide::query::{self, Client, Monitor};
use hyproxide::workspace::WorkspaceId;
use tokio::sync::Mutex;
use tracing::{debug, info, warn};

use crate::error::{Error, Result};
use crate::ipc::{CollapseMode, Direction};
use crate::window::WindowPattern;

// ---------------------------------------------------------------------------
// VirtualWorkspace
// ---------------------------------------------------------------------------

/// A user-facing virtual workspace (valid range: 1–9).
///
/// All monitors are synchronised to the same virtual workspace — each monitor
/// shows its own Hyprland workspace that corresponds to this number.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct VirtualWorkspace(NonZeroU8);

impl VirtualWorkspace {
    const FIRST: Self = Self(NonZeroU8::MIN);

    pub fn new(n: u8) -> Result<Self> {
        NonZeroU8::new(n)
            .filter(|n| n.get() <= 9)
            .map(Self)
            .ok_or(Error::InvalidVirtualWorkspace(n))
    }

    /// Virtual workspaces 1 to 9.
    fn all() -> impl Iterator<Item = Self> {
        (1..=9).filter_map(|n| Self::new(n).ok())
    }

    #[cfg(test)]
    pub fn number(self) -> u8 {
        self.0.get()
    }

    pub fn next(self) -> Self {
        Self(NonZeroU8::MIN.saturating_add(self.0.get() % 9))
    }

    pub fn prev(self) -> Self {
        Self(NonZeroU8::MIN.saturating_add((self.0.get() + 7) % 9))
    }

    /// Compute the Hyprland workspace ID for this virtual workspace on the
    /// given monitor slot: at most 2559, so the sum cannot saturate.
    pub fn hyprland_id(self, slot: MonitorSlot) -> WorkspaceId {
        WorkspaceId::from(NonZeroU16::from(self.0).saturating_add(u16::from(slot.0) * 10))
    }

    /// Extract the virtual workspace from a Hyprland workspace ID.
    /// Returns `None` for orphan IDs (multiples of 10).
    pub fn from_hyprland_id(id: WorkspaceId) -> Option<Self> {
        NonZeroU8::new(u8::try_from(id.get() % 10).ok()?).map(Self)
    }
}

impl std::fmt::Display for VirtualWorkspace {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

// ---------------------------------------------------------------------------
// MonitorSlot
// ---------------------------------------------------------------------------

/// A stable index (0, 1, 2, …) assigned to a physical monitor.
///
/// Slots are assigned by sorting monitors by their description (which contains
/// the serial number), so the same physical monitor always gets the same slot
/// regardless of connector name or Hyprland ID.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct MonitorSlot(u8);

impl MonitorSlot {
    pub fn new(index: u8) -> Self {
        Self(index)
    }

    pub fn index(self) -> u8 {
        self.0
    }

    /// The orphan workspace ID for this slot (10, 20, …). Slot 0 has none:
    /// Hyprland has no workspace 0. These workspaces are never valid —
    /// clients on them need rescuing.
    pub fn orphan_workspace_id(self) -> Option<WorkspaceId> {
        NonZeroU16::new(u16::from(self.0) * 10).map(WorkspaceId::from)
    }

    /// Extract the monitor slot from a Hyprland workspace ID, `None` for IDs
    /// past the last slot.
    pub fn from_hyprland_id(id: WorkspaceId) -> Option<Self> {
        u8::try_from(id.get() / 10).ok().map(Self)
    }
}

// ---------------------------------------------------------------------------
// MonitorRegistry
// ---------------------------------------------------------------------------

/// What the registry knows each of `monitors` by: its description, which
/// contains the serial number, or its name when it has no description, as a
/// headless output has none. A description that several of the monitors
/// have, such as that of two panels of one model without a serial number,
/// also gets the name of each, so every monitor has a slot of its own.
fn registry_keys(monitors: &[Monitor]) -> Vec<String> {
    fn key(monitor: &Monitor) -> &str {
        if monitor.description.is_empty() {
            &monitor.name
        } else {
            &monitor.description
        }
    }
    monitors
        .iter()
        .map(|monitor| {
            let alike = monitors.iter().filter(|other| key(other) == key(monitor));
            if alike.count() > 1 {
                format!("{} ({})", key(monitor), monitor.name)
            } else {
                key(monitor).to_owned()
            }
        })
        .collect()
}

/// Persistent registry of monitor keys ([`registry_keys`]) to slot indices.
/// Stored as one key per line; the line number (0-indexed) is the slot.
/// The built-in display (eDP) is always slot 0 when seeding.
struct MonitorRegistry {
    entries: Vec<String>,
}

impl MonitorRegistry {
    fn path() -> PathBuf {
        let state_dir = std::env::var("XDG_STATE_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| {
                let home = std::env::var("HOME").expect("HOME not set");
                PathBuf::from(home).join(".local/state")
            });
        state_dir.join("hypr-workspaced").join("monitors")
    }

    fn load() -> Self {
        let entries = match std::fs::read_to_string(Self::path()) {
            Ok(content) => content
                .lines()
                .filter(|l| !l.is_empty())
                .map(String::from)
                .collect(),
            Err(_) => Vec::new(),
        };
        Self { entries }
    }

    fn save(&self) {
        let path = Self::path();
        if let Some(parent) = path.parent() {
            if let Err(e) = std::fs::create_dir_all(parent) {
                warn!("Failed to create registry directory: {e}");
                return;
            }
        }
        if let Err(e) = std::fs::write(&path, self.entries.join("\n") + "\n") {
            warn!("Failed to save monitor registry: {e}");
        }
    }

    fn slot_for(&self, key: &str) -> Option<usize> {
        self.entries.iter().position(|d| d == key)
    }

    /// Register monitors by their keys and return whether the registry was
    /// modified. On first run, monitors are sorted by description. New
    /// monitors are appended and get the next available slot.
    fn register<'a>(&mut self, keys: impl IntoIterator<Item = &'a str>) -> bool {
        let mut modified = false;

        if self.entries.is_empty() {
            self.entries.extend(keys.into_iter().map(String::from));
            modified = !self.entries.is_empty();
        } else {
            for key in keys {
                if self.slot_for(key).is_none() {
                    info!("New monitor: {key}, slot {}", self.entries.len());
                    self.entries.push(key.to_owned());
                    modified = true;
                }
            }
        }

        modified
    }
}

// ---------------------------------------------------------------------------
// MonitorLayout
// ---------------------------------------------------------------------------

/// Mapping from Hyprland monitor IDs to stable monitor slots.
pub struct MonitorLayout {
    slots: HashMap<MonitorId, MonitorSlot>,
}

impl MonitorLayout {
    pub fn new() -> Self {
        Self {
            slots: HashMap::new(),
        }
    }

    /// Build a layout using the persistent monitor registry.
    /// Each physical monitor (identified by description/serial) gets a permanent
    /// slot that survives disconnects and restarts.
    pub fn assign(monitors: &[Monitor]) -> Self {
        let keys = registry_keys(monitors);
        let mut registry = MonitorRegistry::load();
        if registry.register(keys.iter().map(String::as_str)) {
            registry.save();
        }

        let mut slots = HashMap::new();
        for (monitor, key) in monitors.iter().zip(&keys) {
            let Some(index) = registry.slot_for(key) else {
                continue;
            };
            let Ok(index) = u8::try_from(index) else {
                warn!(
                    "No slot left for {} ({})",
                    monitor.name, monitor.description
                );
                continue;
            };
            let slot = MonitorSlot::new(index);
            debug!(
                "Slot {} -> {} (id={}, {})",
                slot.index(),
                monitor.name,
                monitor.id,
                monitor.description
            );
            let _earlier_slot_of_a_monitor_listed_twice = slots.insert(monitor.id, slot);
        }

        Self { slots }
    }

    /// Look up the slot for a Hyprland monitor ID.
    /// Falls back to treating the raw ID as a slot index if no mapping exists,
    /// and to `None` for an ID that is no slot index.
    pub fn slot_for(&self, monitor_id: MonitorId) -> Option<MonitorSlot> {
        self.slots
            .get(&monitor_id)
            .copied()
            .or_else(|| u8::try_from(monitor_id.get()).ok().map(MonitorSlot::new))
    }

    /// The slot of a monitor that the daemon acts on.
    fn slot_of(&self, monitor: &Monitor) -> Result<MonitorSlot> {
        self.slot_for(monitor.id)
            .ok_or_else(|| Error::NoSlot(monitor.name.clone()))
    }

    /// Build a reverse mapping: slot → monitor name.
    pub fn slot_to_monitor_name<'a>(
        &self,
        monitors: &'a [Monitor],
    ) -> HashMap<MonitorSlot, &'a str> {
        monitors
            .iter()
            .filter_map(|m| Some((self.slot_for(m.id)?, m.name.as_str())))
            .collect()
    }

    /// Iterate all assigned slots (useful for orphan cleanup).
    pub fn all_slots(&self) -> impl Iterator<Item = MonitorSlot> + '_ {
        let max = self.slots.values().map(|s| s.index()).max().unwrap_or(0);
        (0..=max).map(MonitorSlot::new)
    }
}

/// Check whether a Hyprland workspace ID belongs to a valid virtual workspace
/// on an existing monitor slot.
fn is_valid_workspace(id: WorkspaceId, num_monitors: usize) -> bool {
    VirtualWorkspace::from_hyprland_id(id).is_some()
        && MonitorSlot::from_hyprland_id(id)
            .is_some_and(|slot| usize::from(slot.index()) < num_monitors)
}

// ---------------------------------------------------------------------------
// Requests to Hyprland
// ---------------------------------------------------------------------------

/// Focus a workspace on the monitor that holds it.
fn focus_workspace(workspace: WorkspaceId) -> Focus {
    Focus::Workspace {
        workspace: workspace.into(),
        on_current_monitor: false,
    }
}

/// Move a window to a workspace, and follow it with the focus if `follow`.
fn move_window(window: Address, workspace: WorkspaceId, follow: bool) -> window::Move {
    window::move_window(Movement::Workspace {
        workspace: workspace.into(),
        follow,
    })
    .window(window)
}

/// Move a workspace to the monitor with this name.
fn move_workspace(workspace: WorkspaceId, monitor: &str) -> workspace::MoveToMonitor {
    workspace::move_to_monitor(MonitorSelector::Name(monitor.to_owned())).workspace(workspace)
}

// ---------------------------------------------------------------------------
// WorkspaceManager
// ---------------------------------------------------------------------------

pub struct WorkspaceManager {
    instance: Instance,
    pinned_patterns: Vec<WindowPattern>,
    ipc_lock: Mutex<()>,
    layout: MonitorLayout,
}

impl WorkspaceManager {
    pub fn new(instance: Instance) -> Self {
        Self {
            instance,
            pinned_patterns: Vec::new(),
            ipc_lock: Mutex::new(()),
            layout: MonitorLayout::new(),
        }
    }

    pub fn pin(&mut self, pattern_str: &str) -> Result<()> {
        let pattern = WindowPattern::parse(pattern_str)
            .ok_or_else(|| Error::InvalidWindowPattern(pattern_str.to_string()))?;

        if !self.pinned_patterns.contains(&pattern) {
            info!("Pinning windows matching: {pattern}");
            self.pinned_patterns.push(pattern);
        }
        Ok(())
    }

    pub fn unpin(&mut self, pattern_str: &str) -> Result<()> {
        let pattern = WindowPattern::parse(pattern_str)
            .ok_or_else(|| Error::InvalidWindowPattern(pattern_str.to_string()))?;

        if let Some(pos) = self.pinned_patterns.iter().position(|p| p == &pattern) {
            let unpinned = self.pinned_patterns.remove(pos);
            info!("Unpinning windows matching: {unpinned}");
        }
        Ok(())
    }

    pub fn pins(&self) -> Vec<String> {
        self.pinned_patterns
            .iter()
            .map(ToString::to_string)
            .collect()
    }

    fn is_pinned(&self, client: &Client) -> bool {
        self.pinned_patterns.iter().any(|p| p.matches(client))
    }

    fn find_monitor_for_client(client: &Client, monitors: &[Monitor]) -> Option<MonitorId> {
        client.monitor.or_else(|| {
            let workspace = client.workspace.address.id()?;
            monitors
                .iter()
                .find(|m| m.active_workspace.address.id() == Some(workspace))
                .map(|m| m.id)
        })
    }

    async fn move_pinned_windows(&self, vws: VirtualWorkspace) -> Result<()> {
        if self.pinned_patterns.is_empty() {
            return Ok(());
        }

        let clients = query::clients(&self.instance).await?;
        let monitors = query::monitors(&self.instance).await?;

        for client in &clients {
            if !self.is_pinned(client) {
                continue;
            }

            let Some(client_ws) = client.workspace.address.id() else {
                continue;
            };

            let Some(slot) = Self::find_monitor_for_client(client, &monitors)
                .and_then(|monitor| self.layout.slot_for(monitor))
            else {
                warn!(
                    "Could not determine monitor for pinned client {}",
                    client.address
                );
                continue;
            };

            let target_ws = vws.hyprland_id(slot);

            if client_ws != target_ws {
                debug!(
                    "Moving pinned window {} ({}) from workspace {client_ws} to {target_ws}",
                    client.class, client.address
                );
                dispatch::dispatch(
                    &self.instance,
                    move_window(client.address, target_ws, false),
                )
                .await?;
            }
        }

        Ok(())
    }

    pub async fn assign_workspaces(&mut self) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let monitors = query::monitors(&self.instance).await?;

        if monitors.is_empty() {
            return Err(Error::NoMonitors);
        }

        info!("Assigning workspaces to {} monitor(s)", monitors.len());

        self.layout = MonitorLayout::assign(&monitors);

        for monitor in &monitors {
            let slot = self.layout.slot_of(monitor)?;
            for vws in VirtualWorkspace::all() {
                let rule = rule::workspace_rule(vws.hyprland_id(slot))
                    .monitor(&monitor.name)
                    .persistent(true)
                    .default(vws == VirtualWorkspace::FIRST);

                debug!("Setting workspace rule: {rule}");
                rule::apply(&self.instance, &rule).await?;
            }
        }

        self.cleanup_orphan_workspaces().await?;
        self.move_workspaces_to_correct_monitors(&monitors).await?;

        let focused = active_monitor(&self.instance).await?;
        let target = focused
            .active_workspace
            .address
            .id()
            .and_then(VirtualWorkspace::from_hyprland_id)
            .unwrap_or(VirtualWorkspace::FIRST);

        for monitor in &monitors {
            let target_wsid = target.hyprland_id(self.layout.slot_of(monitor)?);
            if monitor.active_workspace.address.id() == Some(target_wsid) {
                continue;
            }
            debug!(
                "Syncing {} to workspace {target_wsid} (virtual {target})",
                monitor.name
            );
            dispatch::dispatch(&self.instance, focus_workspace(target_wsid)).await?;
        }

        info!("Workspace assignment complete");
        Ok(())
    }

    async fn cleanup_orphan_workspaces(&self) -> Result<()> {
        let clients = query::clients(&self.instance).await?;

        for slot in self.layout.all_slots() {
            let Some(orphan_id) = slot.orphan_workspace_id() else {
                continue;
            };
            let target = VirtualWorkspace::FIRST.hyprland_id(slot);

            let orphan_clients = clients
                .iter()
                .filter(|c| c.workspace.address.id() == Some(orphan_id));

            for client in orphan_clients {
                debug!(
                    "Moving client {} from orphan workspace {orphan_id} to {target}",
                    client.address
                );
                dispatch::dispatch(&self.instance, move_window(client.address, target, false))
                    .await?;
            }
        }

        Ok(())
    }

    async fn move_workspaces_to_correct_monitors(&self, monitors: &[Monitor]) -> Result<()> {
        let workspaces = query::workspaces(&self.instance).await?;
        let slot_to_monitor = self.layout.slot_to_monitor_name(monitors);

        for ws in &workspaces {
            let Some(id) = ws
                .workspace
                .address
                .id()
                .filter(|&id| VirtualWorkspace::from_hyprland_id(id).is_some())
            else {
                continue;
            };

            let Some(expected_name) = MonitorSlot::from_hyprland_id(id)
                .and_then(|slot| slot_to_monitor.get(&slot).copied())
            else {
                continue;
            };

            if ws.monitor.as_deref() == Some(expected_name) {
                continue;
            }

            info!(
                "Moving workspace {id} from {} to {expected_name}",
                ws.monitor.as_deref().unwrap_or("no monitor")
            );
            dispatch::dispatch(&self.instance, move_workspace(id, expected_name)).await?;
        }

        Ok(())
    }

    pub async fn switch_virtual(&self, vws: VirtualWorkspace) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let focused = active_monitor(&self.instance).await?;
        let wsid = vws.hyprland_id(self.layout.slot_of(&focused)?);

        debug!(
            "Switching to virtual workspace {vws} (workspace {wsid} on {})",
            focused.name
        );

        dispatch::dispatch(&self.instance, focus_workspace(wsid)).await?;

        Ok(())
    }

    pub async fn sync_monitors(&self, trigger_workspace_id: WorkspaceId) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let Some(vws) = VirtualWorkspace::from_hyprland_id(trigger_workspace_id) else {
            return Ok(());
        };

        let monitors = query::monitors(&self.instance).await?;

        if monitors.len() <= 1 {
            return Ok(());
        }

        debug!(
            "Syncing monitors to virtual workspace {vws} (triggered by ws {trigger_workspace_id})"
        );

        let workspaces = query::workspaces(&self.instance).await?;

        for monitor in &monitors {
            let Some(slot) = self.layout.slot_for(monitor.id) else {
                continue;
            };
            let target_wsid = vws.hyprland_id(slot);
            if target_wsid == trigger_workspace_id
                || monitor.active_workspace.address.id() == Some(target_wsid)
            {
                continue;
            }

            // If the workspace is on the wrong monitor, move it there first
            if let Some(ws) = workspaces
                .iter()
                .find(|w| w.workspace.address.id() == Some(target_wsid))
            {
                if ws.monitor.as_deref() != Some(&monitor.name) {
                    warn!(
                        "Workspace {target_wsid} is on {} but belongs on {}, relocating",
                        ws.monitor.as_deref().unwrap_or("no monitor"),
                        monitor.name
                    );
                    if let Err(e) = dispatch::dispatch(
                        &self.instance,
                        move_workspace(target_wsid, &monitor.name),
                    )
                    .await
                    {
                        warn!(
                            "Failed to move workspace {target_wsid} to {}: {e}",
                            monitor.name
                        );
                    }
                }
            }

            debug!("Switching {} to workspace {target_wsid}", monitor.name);
            if let Err(e) = dispatch::dispatch(&self.instance, focus_workspace(target_wsid)).await {
                warn!(
                    "Failed to switch {} to workspace {target_wsid}: {e}",
                    monitor.name
                );
            }
        }

        if let Err(e) = self.move_pinned_windows(vws).await {
            warn!("Failed to move pinned windows: {e}");
        }

        let active_ws = query::active_workspace(&self.instance).await?;
        if active_ws.workspace.address.id() != Some(trigger_workspace_id) {
            if let Err(e) =
                dispatch::dispatch(&self.instance, focus_workspace(trigger_workspace_id)).await
            {
                warn!("Failed to refocus trigger workspace {trigger_workspace_id}: {e}");
            }
        }

        if let Err(e) = self.focus_window_under_cursor(vws).await {
            warn!("Failed to focus window under cursor: {e}");
        }

        Ok(())
    }

    async fn focus_window_under_cursor(&self, vws: VirtualWorkspace) -> Result<()> {
        let cursor = query::cursor_position(&self.instance).await?;
        let clients = query::clients(&self.instance).await?;
        let monitors = query::monitors(&self.instance).await?;

        let valid_workspaces: Vec<WorkspaceId> = monitors
            .iter()
            .filter_map(|m| Some(vws.hyprland_id(self.layout.slot_for(m.id)?)))
            .collect();

        let window_under_cursor = clients.iter().find(|c| {
            c.workspace
                .address
                .id()
                .is_some_and(|id| valid_workspaces.contains(&id))
                && (c.at.x..c.at.x + c.size.width).contains(&cursor.x)
                && (c.at.y..c.at.y + c.size.height).contains(&cursor.y)
        });

        if let Some(client) = window_under_cursor {
            debug!("Focusing window under cursor: {}", client.class);
            dispatch::dispatch(&self.instance, Focus::Window(client.address.into())).await?;
        }

        Ok(())
    }

    /// Prime pointer focus on startup.
    ///
    /// With `input:follow_mouse = 1`, Hyprland does not compute the
    /// window-under-cursor focus until the first real pointer motion, so a
    /// freshly started session leaves every window unfocused until the mouse is
    /// moved or a workspace is switched. Replaying the same focus logic the
    /// workspace-switch path uses primes that state without warping the cursor.
    pub async fn prime_focus(&self) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let focused = active_monitor(&self.instance).await?;
        let Some(vws) = focused
            .active_workspace
            .address
            .id()
            .and_then(VirtualWorkspace::from_hyprland_id)
        else {
            return Ok(());
        };

        self.focus_window_under_cursor(vws).await
    }

    pub async fn move_to_virtual(&self, vws: VirtualWorkspace) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let focused = active_monitor(&self.instance).await?;
        let wsid = vws.hyprland_id(self.layout.slot_of(&focused)?);

        debug!("Moving active window to workspace {wsid} (virtual {vws})");

        let move_active = window::move_window(Movement::Workspace {
            workspace: wsid.into(),
            follow: true,
        });
        dispatch::dispatch(&self.instance, move_active).await?;

        Ok(())
    }

    /// Swap windows between the focused monitor and its physical neighbor.
    /// Only affects the current virtual workspace. Windows are moved individually
    /// so that workspace IDs stay bound to their correct monitors.
    pub async fn swap_monitor(&self, direction: Direction) -> Result<()> {
        /// The workspace that holds the windows of the focused monitor while
        /// the windows of the other one move in.
        const BUFFER_WS: NonZeroU16 = NonZeroU16::new(999).unwrap();

        let _guard = self.ipc_lock.lock().await;

        let monitors = query::monitors(&self.instance).await?;
        if monitors.len() < 2 {
            return Ok(());
        }

        let focused = active_monitor(&self.instance).await?;

        let mut by_position: Vec<_> = monitors.iter().collect();
        by_position.sort_by_key(|m| m.x);

        let focused_idx = by_position
            .iter()
            .position(|m| m.id == focused.id)
            .ok_or_else(|| Error::Other("Focused monitor not found in list".into()))?;

        let target_idx = match direction {
            Direction::Next => {
                if focused_idx + 1 >= by_position.len() {
                    return Ok(());
                }
                focused_idx + 1
            }
            Direction::Prev => {
                if focused_idx == 0 {
                    return Ok(());
                }
                focused_idx - 1
            }
        };

        let target = by_position[target_idx];

        let Some(vws) = focused
            .active_workspace
            .address
            .id()
            .and_then(VirtualWorkspace::from_hyprland_id)
        else {
            return Ok(());
        };

        let ws_a = vws.hyprland_id(self.layout.slot_of(&focused)?);
        let ws_b = vws.hyprland_id(self.layout.slot_of(target)?);

        let clients = query::clients(&self.instance).await?;
        let on = |workspace: WorkspaceId| -> Vec<Address> {
            clients
                .iter()
                .filter(|c| c.workspace.address.id() == Some(workspace))
                .map(|c| c.address)
                .collect()
        };
        let clients_a = on(ws_a);
        let clients_b = on(ws_b);

        debug!(
            "Swapping ws {ws_a} ({}, {} windows) <-> ws {ws_b} ({}, {} windows)",
            focused.name,
            clients_a.len(),
            target.name,
            clients_b.len(),
        );

        let moves = clients_a
            .iter()
            .map(|&window| (window, WorkspaceId::from(BUFFER_WS)))
            .chain(clients_b.iter().map(|&window| (window, ws_a)))
            .chain(clients_a.iter().map(|&window| (window, ws_b)));
        for (window, workspace) in moves {
            dispatch::dispatch(&self.instance, move_window(window, workspace, false)).await?;
        }

        Ok(())
    }

    pub async fn navigate(&self, direction: Direction) -> Result<()> {
        let monitors = query::monitors(&self.instance).await?;

        let primary = monitors
            .iter()
            .find(|m| self.layout.slot_for(m.id) == Some(MonitorSlot::new(0)));

        let Some(primary) = primary else {
            warn!("No primary monitor found");
            return Ok(());
        };

        let Some(current) = primary
            .active_workspace
            .address
            .id()
            .and_then(VirtualWorkspace::from_hyprland_id)
        else {
            warn!("Primary monitor on special/orphan workspace");
            return Ok(());
        };

        let target = match direction {
            Direction::Next => current.next(),
            Direction::Prev => current.prev(),
        };

        debug!("Navigating {direction:?}: virtual {current} -> {target}");

        self.switch_virtual(target).await
    }

    pub async fn collapse(&self, mode: CollapseMode) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let Some(current_ws_id) = query::active_workspace(&self.instance)
            .await?
            .workspace
            .address
            .id()
        else {
            return Ok(());
        };

        let Some(current_vws) = VirtualWorkspace::from_hyprland_id(current_ws_id) else {
            return Ok(());
        };

        let clients = query::clients(&self.instance).await?;
        let monitors = query::monitors(&self.instance).await?;
        let num_monitors = monitors.len();

        debug!("Collapsing {mode:?} to workspace {current_ws_id} (virtual {current_vws})");

        for client in &clients {
            let Some(client_ws_id) = client.workspace.address.id() else {
                continue;
            };

            let should_move = match mode {
                CollapseMode::All => {
                    VirtualWorkspace::from_hyprland_id(client_ws_id) == Some(current_vws)
                        && client_ws_id != current_ws_id
                }
                CollapseMode::Invisible => !is_valid_workspace(client_ws_id, num_monitors),
            };

            if should_move {
                debug!(
                    "Moving client {} from workspace {client_ws_id} to {current_ws_id}",
                    client.address
                );
                dispatch::dispatch(
                    &self.instance,
                    move_window(client.address, current_ws_id, true),
                )
                .await?;
            }
        }

        Ok(())
    }
}

/// The focused monitor.
async fn active_monitor(instance: &Instance) -> Result<Monitor> {
    query::monitors(instance)
        .await?
        .into_iter()
        .find(|monitor| monitor.flags.contains(query::MonitorFlag::Focused))
        .ok_or(Error::NoFocusedMonitor)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn id(number: u32) -> WorkspaceId {
        WorkspaceId::try_from(number).unwrap()
    }

    #[test]
    fn virtual_workspace_validation() {
        assert!(VirtualWorkspace::new(0).is_err());
        assert!(VirtualWorkspace::new(10).is_err());
        for n in 1..=9 {
            assert_eq!(VirtualWorkspace::new(n).unwrap().number(), n);
        }
        let all: Vec<_> = VirtualWorkspace::all()
            .map(VirtualWorkspace::number)
            .collect();
        assert_eq!(all, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    }

    #[test]
    fn virtual_workspace_navigation() {
        let ws = VirtualWorkspace::new(1).unwrap();
        assert_eq!(ws.next().number(), 2);
        assert_eq!(ws.prev().number(), 9);

        let ws = VirtualWorkspace::new(9).unwrap();
        assert_eq!(ws.next().number(), 1);
        assert_eq!(ws.prev().number(), 8);

        let ws = VirtualWorkspace::new(5).unwrap();
        assert_eq!(ws.next().number(), 6);
        assert_eq!(ws.prev().number(), 4);
    }

    #[test]
    fn hyprland_id_mapping() {
        let slot0 = MonitorSlot::new(0);
        let slot1 = MonitorSlot::new(1);
        let slot2 = MonitorSlot::new(2);
        let last = MonitorSlot::new(u8::MAX);
        let vws = |n| VirtualWorkspace::new(n).unwrap();

        // slot 0 -> workspaces 1-9
        assert_eq!(vws(1).hyprland_id(slot0), id(1));
        assert_eq!(vws(9).hyprland_id(slot0), id(9));
        // slot 1 -> workspaces 11-19
        assert_eq!(vws(1).hyprland_id(slot1), id(11));
        assert_eq!(vws(4).hyprland_id(slot1), id(14));
        // slot 2 -> workspaces 21-29
        assert_eq!(vws(1).hyprland_id(slot2), id(21));
        assert_eq!(vws(9).hyprland_id(last), id(2559));
    }

    #[test]
    fn from_hyprland_id() {
        // Normal workspace IDs
        assert_eq!(
            VirtualWorkspace::from_hyprland_id(id(1)).unwrap().number(),
            1
        );
        assert_eq!(
            VirtualWorkspace::from_hyprland_id(id(9)).unwrap().number(),
            9
        );
        assert_eq!(
            VirtualWorkspace::from_hyprland_id(id(14)).unwrap().number(),
            4
        );
        assert_eq!(
            VirtualWorkspace::from_hyprland_id(id(23)).unwrap().number(),
            3
        );

        // Orphan IDs
        assert!(VirtualWorkspace::from_hyprland_id(id(10)).is_none());
        assert!(VirtualWorkspace::from_hyprland_id(id(20)).is_none());
    }

    #[test]
    fn monitor_slot_from_hyprland_id() {
        let slot = |n| MonitorSlot::from_hyprland_id(id(n)).map(MonitorSlot::index);
        assert_eq!(slot(1), Some(0));
        assert_eq!(slot(9), Some(0));
        assert_eq!(slot(11), Some(1));
        assert_eq!(slot(14), Some(1));
        assert_eq!(slot(21), Some(2));
        assert_eq!(slot(2559), Some(255));
        assert_eq!(slot(2560), None);
    }

    #[test]
    fn registry_gives_each_key_one_slot() {
        let mut registry = MonitorRegistry {
            entries: Vec::new(),
        };
        assert!(registry.register(["eDP-1 panel", "HEADLESS-2"]));
        assert!(!registry.register(["HEADLESS-2", "eDP-1 panel"]));
        assert!(registry.register(["HEADLESS-3", "eDP-1 panel"]));
        assert_eq!(registry.slot_for("eDP-1 panel"), Some(0));
        assert_eq!(registry.slot_for("HEADLESS-2"), Some(1));
        assert_eq!(registry.slot_for("HEADLESS-3"), Some(2));
    }

    #[test]
    fn monitors_with_one_description_get_a_slot_each() {
        let mut monitors: Vec<Monitor> = serde_json::from_str(include_str!(
            "../testdata/hyprland-answers/monitors-all-two-outputs.json"
        ))
        .unwrap();
        for monitor in &mut monitors {
            "Dell Inc. DELL U2720Q".clone_into(&mut monitor.description);
        }
        let keys = registry_keys(&monitors);
        assert_eq!(
            keys,
            [
                "Dell Inc. DELL U2720Q (Virtual-1)",
                "Dell Inc. DELL U2720Q (HYPR-WORKSPACED-1)"
            ]
        );
        let mut registry = MonitorRegistry {
            entries: Vec::new(),
        };
        assert!(registry.register(keys.iter().map(String::as_str)));
        assert_eq!(registry.slot_for(&keys[0]), Some(0));
        assert_eq!(registry.slot_for(&keys[1]), Some(1));

        assert_eq!(registry_keys(&monitors[1..]), ["Dell Inc. DELL U2720Q"]);
    }

    #[test]
    fn orphan_workspace_ids() {
        assert_eq!(MonitorSlot::new(0).orphan_workspace_id(), None);
        assert_eq!(MonitorSlot::new(1).orphan_workspace_id(), Some(id(10)));
        assert_eq!(MonitorSlot::new(2).orphan_workspace_id(), Some(id(20)));
    }
}

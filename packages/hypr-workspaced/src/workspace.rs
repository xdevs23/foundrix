use std::collections::HashMap;
use std::path::PathBuf;

use hyprland::data::{Client, Monitor};
use hyprland::shared::WorkspaceId;
use tokio::sync::Mutex;
use tracing::{debug, info, warn};

use crate::error::{Error, Result};
use crate::ipc::{CollapseMode, Direction};
use crate::query;
use crate::request::Request;
use crate::window::WindowPattern;

// ---------------------------------------------------------------------------
// VirtualWorkspace
// ---------------------------------------------------------------------------

/// A user-facing virtual workspace (valid range: 1–9).
///
/// All monitors are synchronised to the same virtual workspace — each monitor
/// shows its own Hyprland workspace that corresponds to this number.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct VirtualWorkspace(u8);

impl VirtualWorkspace {
    pub fn new(n: u8) -> Result<Self> {
        if (1..=9).contains(&n) {
            Ok(Self(n))
        } else {
            Err(Error::InvalidVirtualWorkspace(n))
        }
    }

    #[cfg(test)]
    pub fn number(self) -> u8 {
        self.0
    }

    pub fn next(self) -> Self {
        Self((self.0 % 9) + 1)
    }

    pub fn prev(self) -> Self {
        Self(((self.0 + 7) % 9) + 1)
    }

    /// Compute the Hyprland workspace ID for this virtual workspace on the
    /// given monitor slot.
    pub fn hyprland_id(self, slot: MonitorSlot) -> WorkspaceId {
        slot.0 as WorkspaceId * 10 + self.0 as WorkspaceId
    }

    /// Extract the virtual workspace from a raw Hyprland workspace ID.
    /// Returns `None` for special (negative) or orphan (multiples of 10) IDs.
    pub fn from_hyprland_id(id: WorkspaceId) -> Option<Self> {
        if id <= 0 || id % 10 == 0 {
            return None;
        }
        let n = (((id - 1) % 10) + 1) as u8;
        Some(Self(n))
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

    /// The orphan workspace ID for this slot (0, 10, 20, …).
    /// These workspaces are never valid — clients on them need rescuing.
    pub fn orphan_workspace_id(self) -> WorkspaceId {
        self.0 as WorkspaceId * 10
    }

    /// Extract the monitor slot from a raw Hyprland workspace ID.
    pub fn from_hyprland_id(id: WorkspaceId) -> Self {
        if id < 10 {
            Self(0)
        } else {
            Self((id / 10) as u8)
        }
    }
}

// ---------------------------------------------------------------------------
// MonitorRegistry
// ---------------------------------------------------------------------------

/// Persistent registry of monitor descriptions to slot indices.
/// Stored as one description per line; the line number (0-indexed) is the slot.
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

    fn slot_for(&self, description: &str) -> Option<usize> {
        self.entries.iter().position(|d| d == description)
    }

    /// Register monitors and return whether the registry was modified.
    /// On first run, monitors are sorted by description. New monitors are
    /// appended and get the next available slot.
    fn register(&mut self, monitors: &[Monitor]) -> bool {
        let mut modified = false;

        if self.entries.is_empty() {
            for m in monitors {
                self.entries.push(m.description.clone());
            }
            modified = !self.entries.is_empty();
        } else {
            for monitor in monitors {
                if self.slot_for(&monitor.description).is_none() {
                    info!(
                        "New monitor: {} ({}), slot {}",
                        monitor.name,
                        monitor.description,
                        self.entries.len()
                    );
                    self.entries.push(monitor.description.clone());
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
    slots: HashMap<i128, MonitorSlot>,
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
        let mut registry = MonitorRegistry::load();
        if registry.register(monitors) {
            registry.save();
        }

        let mut slots = HashMap::new();
        for monitor in monitors {
            if let Some(slot_idx) = registry.slot_for(&monitor.description) {
                let slot = MonitorSlot::new(slot_idx as u8);
                debug!(
                    "Slot {} -> {} (id={}, {})",
                    slot.index(),
                    monitor.name,
                    monitor.id,
                    monitor.description
                );
                slots.insert(monitor.id, slot);
            }
        }

        Self { slots }
    }

    /// Look up the slot for a Hyprland monitor ID.
    /// Falls back to treating the raw ID as a slot index if no mapping exists.
    pub fn slot_for(&self, monitor_id: i128) -> MonitorSlot {
        self.slots
            .get(&monitor_id)
            .copied()
            .unwrap_or(MonitorSlot::new(monitor_id as u8))
    }

    /// Build a reverse mapping: slot → monitor name.
    pub fn slot_to_monitor_name<'a>(
        &self,
        monitors: &'a [Monitor],
    ) -> HashMap<MonitorSlot, &'a str> {
        monitors
            .iter()
            .map(|m| (self.slot_for(m.id), m.name.as_str()))
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
    VirtualWorkspace::from_hyprland_id(id)
        .map(|_| {
            let slot = MonitorSlot::from_hyprland_id(id);
            (slot.index() as usize) < num_monitors
        })
        .unwrap_or(false)
}

// ---------------------------------------------------------------------------
// WorkspaceManager
// ---------------------------------------------------------------------------

pub struct WorkspaceManager {
    pinned_patterns: Vec<WindowPattern>,
    ipc_lock: Mutex<()>,
    layout: MonitorLayout,
}

impl WorkspaceManager {
    pub fn new() -> Self {
        Self {
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
            info!("Unpinning windows matching: {pattern}");
            self.pinned_patterns.remove(pos);
        }
        Ok(())
    }

    pub fn pins(&self) -> Vec<String> {
        self.pinned_patterns.iter().map(|p| p.to_string()).collect()
    }

    fn is_pinned(&self, client: &Client) -> bool {
        self.pinned_patterns.iter().any(|p| p.matches(client))
    }

    async fn find_monitor_for_client(client: &Client, monitors: &[Monitor]) -> Option<i128> {
        client.monitor.or_else(|| {
            monitors
                .iter()
                .find(|m| m.active_workspace.id == client.workspace.id)
                .map(|m| m.id)
        })
    }

    async fn move_pinned_windows(&self, vws: VirtualWorkspace) -> Result<()> {
        if self.pinned_patterns.is_empty() {
            return Ok(());
        }

        let clients = query::clients().await?;
        let monitors = query::monitors().await?;

        for client in &clients {
            if !self.is_pinned(client) {
                continue;
            }

            if client.workspace.id < 0 {
                continue;
            }

            let monitor_id = match Self::find_monitor_for_client(client, &monitors).await {
                Some(id) => id,
                None => {
                    warn!(
                        "Could not determine monitor for pinned client {}",
                        client.address
                    );
                    continue;
                }
            };

            let target_ws = vws.hyprland_id(self.layout.slot_for(monitor_id));

            if client.workspace.id != target_ws {
                debug!(
                    "Moving pinned window {} ({}) from workspace {} to {}",
                    client.class, client.address, client.workspace.id, target_ws
                );
                Request::MoveWindowSilent {
                    window: &client.address,
                    workspace: target_ws,
                }
                .send()
                .await?;
            }
        }

        Ok(())
    }

    pub async fn assign_workspaces(&mut self) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let monitors = query::monitors().await?;

        if monitors.is_empty() {
            return Err(Error::NoMonitors);
        }

        info!("Assigning workspaces to {} monitor(s)", monitors.len());

        self.layout = MonitorLayout::assign(&monitors);

        for monitor in &monitors {
            let slot = self.layout.slot_for(monitor.id);
            for n in 1..=9u8 {
                let vws = VirtualWorkspace(n);
                let wsid = vws.hyprland_id(slot);
                let is_default = n == 1;

                let rule = Request::WorkspaceRule {
                    workspace: wsid,
                    monitor: &monitor.name,
                    default: is_default,
                };

                debug!("Setting workspace rule: {}", rule.lua());
                rule.send().await?;
            }
        }

        self.cleanup_orphan_workspaces().await?;
        self.move_workspaces_to_correct_monitors(&monitors).await?;

        let focused = query::active_monitor().await?;
        let target = VirtualWorkspace::from_hyprland_id(focused.active_workspace.id)
            .unwrap_or(VirtualWorkspace(1));

        for monitor in &monitors {
            let target_wsid = target.hyprland_id(self.layout.slot_for(monitor.id));
            if monitor.active_workspace.id == target_wsid {
                continue;
            }
            debug!(
                "Syncing {} to workspace {target_wsid} (virtual {target})",
                monitor.name
            );
            Request::FocusWorkspace(target_wsid).send().await?;
        }

        info!("Workspace assignment complete");
        Ok(())
    }

    async fn cleanup_orphan_workspaces(&self) -> Result<()> {
        let clients = query::clients().await?;

        for slot in self.layout.all_slots() {
            let orphan_id = slot.orphan_workspace_id();
            let target = orphan_id + 1;

            let orphan_clients: Vec<_> = clients
                .iter()
                .filter(|c| c.workspace.id == orphan_id)
                .collect();

            for client in orphan_clients {
                debug!(
                    "Moving client {} from orphan workspace {orphan_id} to {target}",
                    client.address
                );
                Request::MoveWindowSilent {
                    window: &client.address,
                    workspace: target,
                }
                .send()
                .await?;
            }
        }

        Ok(())
    }

    async fn move_workspaces_to_correct_monitors(&self, monitors: &[Monitor]) -> Result<()> {
        let workspaces = query::workspaces().await?;
        let slot_to_monitor = self.layout.slot_to_monitor_name(monitors);

        for ws in &workspaces {
            if ws.id <= 0 || VirtualWorkspace::from_hyprland_id(ws.id).is_none() {
                continue;
            }

            let expected_slot = MonitorSlot::from_hyprland_id(ws.id);
            let expected_name = match slot_to_monitor.get(&expected_slot) {
                Some(name) => *name,
                None => continue,
            };

            if ws.monitor == expected_name {
                continue;
            }

            info!(
                "Moving workspace {} from {} to {}",
                ws.id, ws.monitor, expected_name
            );
            Request::MoveWorkspaceToMonitor {
                workspace: ws.id,
                monitor: expected_name,
            }
            .send()
            .await?;
        }

        Ok(())
    }

    pub async fn switch_virtual(&self, vws: VirtualWorkspace) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let focused = query::active_monitor().await?;
        let wsid = vws.hyprland_id(self.layout.slot_for(focused.id));

        debug!(
            "Switching to virtual workspace {vws} (workspace {wsid} on {})",
            focused.name
        );

        Request::FocusWorkspace(wsid).send().await?;

        Ok(())
    }

    pub async fn sync_monitors(&self, trigger_workspace_id: WorkspaceId) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let vws = match VirtualWorkspace::from_hyprland_id(trigger_workspace_id) {
            Some(v) => v,
            None => return Ok(()),
        };

        let monitors = query::monitors().await?;

        if monitors.len() <= 1 {
            return Ok(());
        }

        debug!(
            "Syncing monitors to virtual workspace {vws} (triggered by ws {trigger_workspace_id})"
        );

        let workspaces = query::workspaces().await?;

        for monitor in &monitors {
            let target_wsid = vws.hyprland_id(self.layout.slot_for(monitor.id));
            if target_wsid == trigger_workspace_id || monitor.active_workspace.id == target_wsid {
                continue;
            }

            // If the workspace is on the wrong monitor, move it there first
            if let Some(ws) = workspaces.iter().find(|w| w.id == target_wsid) {
                if ws.monitor != monitor.name {
                    warn!(
                        "Workspace {target_wsid} is on {} but belongs on {}, relocating",
                        ws.monitor, monitor.name
                    );
                    if let Err(e) = (Request::MoveWorkspaceToMonitor {
                        workspace: target_wsid,
                        monitor: &monitor.name,
                    })
                    .send()
                    .await
                    {
                        warn!("Failed to move workspace {target_wsid} to {}: {e}", monitor.name);
                    }
                }
            }

            debug!("Switching {} to workspace {target_wsid}", monitor.name);
            if let Err(e) = Request::FocusWorkspace(target_wsid).send().await
            {
                warn!(
                    "Failed to switch {} to workspace {target_wsid}: {e}",
                    monitor.name
                );
            }
        }

        if let Err(e) = self.move_pinned_windows(vws).await {
            warn!("Failed to move pinned windows: {e}");
        }

        let active_ws = query::active_workspace().await?;
        if active_ws.id != trigger_workspace_id {
            if let Err(e) = Request::FocusWorkspace(trigger_workspace_id).send().await
            {
                warn!(
                    "Failed to refocus trigger workspace {trigger_workspace_id}: {e}"
                );
            }
        }

        if let Err(e) = self.focus_window_under_cursor(vws).await {
            warn!("Failed to focus window under cursor: {e}");
        }

        Ok(())
    }

    async fn focus_window_under_cursor(&self, vws: VirtualWorkspace) -> Result<()> {
        let cursor = query::cursor_position().await?;
        let clients = query::clients().await?;
        let monitors = query::monitors().await?;

        let valid_workspaces: Vec<WorkspaceId> = monitors
            .iter()
            .map(|m| vws.hyprland_id(self.layout.slot_for(m.id)))
            .collect();

        let window_under_cursor = clients.iter().find(|c| {
            if !valid_workspaces.contains(&c.workspace.id) {
                return false;
            }
            let (wx, wy) = c.at;
            let (ww, wh) = c.size;
            let cx = cursor.x as i16;
            let cy = cursor.y as i16;
            cx >= wx && cx < wx + ww && cy >= wy && cy < wy + wh
        });

        if let Some(client) = window_under_cursor {
            debug!("Focusing window under cursor: {}", client.class);
            Request::FocusWindow(&client.address).send().await?;
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

        let focused = query::active_monitor().await?;
        let vws = match VirtualWorkspace::from_hyprland_id(focused.active_workspace.id) {
            Some(v) => v,
            None => return Ok(()),
        };

        self.focus_window_under_cursor(vws).await
    }

    pub async fn move_to_virtual(&self, vws: VirtualWorkspace) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let focused = query::active_monitor().await?;
        let wsid = vws.hyprland_id(self.layout.slot_for(focused.id));

        debug!("Moving active window to workspace {wsid} (virtual {vws})");

        Request::MoveActiveWindow(wsid).send().await?;

        Ok(())
    }

    /// Swap windows between the focused monitor and its physical neighbor.
    /// Only affects the current virtual workspace. Windows are moved individually
    /// so that workspace IDs stay bound to their correct monitors.
    pub async fn swap_monitor(&self, direction: Direction) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let monitors = query::monitors().await?;
        if monitors.len() < 2 {
            return Ok(());
        }

        let focused = query::active_monitor().await?;

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

        let vws = match VirtualWorkspace::from_hyprland_id(focused.active_workspace.id) {
            Some(v) => v,
            None => return Ok(()),
        };

        let ws_a = vws.hyprland_id(self.layout.slot_for(focused.id));
        let ws_b = vws.hyprland_id(self.layout.slot_for(target.id));

        let clients = query::clients().await?;
        let clients_a: Vec<_> = clients.iter().filter(|c| c.workspace.id == ws_a).collect();
        let clients_b: Vec<_> = clients.iter().filter(|c| c.workspace.id == ws_b).collect();

        debug!(
            "Swapping ws {ws_a} ({}, {} windows) <-> ws {ws_b} ({}, {} windows)",
            focused.name,
            clients_a.len(),
            target.name,
            clients_b.len(),
        );

        const BUFFER_WS: WorkspaceId = 999;

        for client in &clients_a {
            Request::MoveWindowSilent {
                window: &client.address,
                workspace: BUFFER_WS,
            }
            .send()
            .await?;
        }
        for client in &clients_b {
            Request::MoveWindowSilent {
                window: &client.address,
                workspace: ws_a,
            }
            .send()
            .await?;
        }
        for client in &clients_a {
            Request::MoveWindowSilent {
                window: &client.address,
                workspace: ws_b,
            }
            .send()
            .await?;
        }

        Ok(())
    }

    pub async fn navigate(&self, direction: Direction) -> Result<()> {
        let monitors = query::monitors().await?;

        let primary = monitors
            .iter()
            .find(|m| self.layout.slot_for(m.id) == MonitorSlot::new(0));

        let current_ws = match primary {
            Some(m) => m.active_workspace.id,
            None => {
                warn!("No primary monitor found");
                return Ok(());
            }
        };

        let current = match VirtualWorkspace::from_hyprland_id(current_ws) {
            Some(v) => v,
            None => {
                warn!("Primary monitor on special/orphan workspace");
                return Ok(());
            }
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

        let active_ws = query::active_workspace().await?;
        let current_ws_id = active_ws.id;

        let current_vws = match VirtualWorkspace::from_hyprland_id(current_ws_id) {
            Some(v) => v,
            None => return Ok(()),
        };

        let clients = query::clients().await?;
        let monitors = query::monitors().await?;
        let num_monitors = monitors.len();

        debug!("Collapsing {mode:?} to workspace {current_ws_id} (virtual {current_vws})");

        for client in clients.iter() {
            let client_ws_id = client.workspace.id;

            if client_ws_id <= 0 {
                continue;
            }

            let should_move = match mode {
                CollapseMode::All => {
                    VirtualWorkspace::from_hyprland_id(client_ws_id)
                        .map(|v| v == current_vws && client_ws_id != current_ws_id)
                        .unwrap_or(false)
                }
                CollapseMode::Invisible => !is_valid_workspace(client_ws_id, num_monitors),
            };

            if should_move {
                debug!(
                    "Moving client {} from workspace {client_ws_id} to {current_ws_id}",
                    client.address
                );
                Request::MoveWindow {
                    window: &client.address,
                    workspace: current_ws_id,
                }
                .send()
                .await?;
            }
        }

        Ok(())
    }
}

impl Default for WorkspaceManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn virtual_workspace_validation() {
        assert!(VirtualWorkspace::new(0).is_err());
        assert!(VirtualWorkspace::new(10).is_err());
        for n in 1..=9 {
            assert_eq!(VirtualWorkspace::new(n).unwrap().number(), n);
        }
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

        // slot 0 -> workspaces 1-9
        assert_eq!(VirtualWorkspace::new(1).unwrap().hyprland_id(slot0), 1);
        assert_eq!(VirtualWorkspace::new(9).unwrap().hyprland_id(slot0), 9);
        // slot 1 -> workspaces 11-19
        assert_eq!(VirtualWorkspace::new(1).unwrap().hyprland_id(slot1), 11);
        assert_eq!(VirtualWorkspace::new(4).unwrap().hyprland_id(slot1), 14);
        // slot 2 -> workspaces 21-29
        assert_eq!(VirtualWorkspace::new(1).unwrap().hyprland_id(slot2), 21);
    }

    #[test]
    fn from_hyprland_id() {
        // Normal workspace IDs
        assert_eq!(VirtualWorkspace::from_hyprland_id(1).unwrap().number(), 1);
        assert_eq!(VirtualWorkspace::from_hyprland_id(9).unwrap().number(), 9);
        assert_eq!(VirtualWorkspace::from_hyprland_id(14).unwrap().number(), 4);
        assert_eq!(VirtualWorkspace::from_hyprland_id(23).unwrap().number(), 3);

        // Special and orphan IDs
        assert!(VirtualWorkspace::from_hyprland_id(-1).is_none());
        assert!(VirtualWorkspace::from_hyprland_id(0).is_none());
        assert!(VirtualWorkspace::from_hyprland_id(10).is_none());
        assert!(VirtualWorkspace::from_hyprland_id(20).is_none());
    }

    #[test]
    fn monitor_slot_from_hyprland_id() {
        assert_eq!(MonitorSlot::from_hyprland_id(1).index(), 0);
        assert_eq!(MonitorSlot::from_hyprland_id(9).index(), 0);
        assert_eq!(MonitorSlot::from_hyprland_id(11).index(), 1);
        assert_eq!(MonitorSlot::from_hyprland_id(14).index(), 1);
        assert_eq!(MonitorSlot::from_hyprland_id(21).index(), 2);
    }

    #[test]
    fn orphan_workspace_ids() {
        assert_eq!(MonitorSlot::new(0).orphan_workspace_id(), 0);
        assert_eq!(MonitorSlot::new(1).orphan_workspace_id(), 10);
        assert_eq!(MonitorSlot::new(2).orphan_workspace_id(), 20);
    }
}

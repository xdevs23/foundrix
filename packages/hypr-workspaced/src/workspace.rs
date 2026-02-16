use hyprland::data::{Client, Clients, CursorPosition, Monitor, Monitors, Workspace, Workspaces};
use hyprland::dispatch::{
    Dispatch, DispatchType, MonitorIdentifier, WindowIdentifier, WorkspaceIdentifier,
    WorkspaceIdentifierWithSpecial,
};
use hyprland::keyword::Keyword;
use hyprland::shared::{HyprData, HyprDataActive, WorkspaceId};
use tokio::sync::Mutex;
use tracing::{debug, info, warn};

use crate::error::{Error, Result};
use crate::ipc::{CollapseMode, Direction};
use crate::window::WindowPattern;

pub struct WorkspaceManager {
    pinned_patterns: Vec<WindowPattern>,
    /// Lock to serialize IPC operations and prevent race conditions during workspace transitions
    ipc_lock: Mutex<()>,
}

impl WorkspaceManager {
    pub fn new() -> Self {
        Self {
            pinned_patterns: Vec::new(),
            ipc_lock: Mutex::new(()),
        }
    }

    fn workspace_id(virtual_ws: u8, monitor_id: i128) -> WorkspaceId {
        if monitor_id == 0 {
            virtual_ws as WorkspaceId
        } else {
            (monitor_id as WorkspaceId * 10) + virtual_ws as WorkspaceId
        }
    }

    fn virtual_from_workspace(workspace_id: WorkspaceId) -> u8 {
        (((workspace_id - 1) % 10) + 1) as u8
    }

    fn is_special_workspace(workspace_id: WorkspaceId) -> bool {
        workspace_id < 0
    }

    /// Check if a workspace ID is valid for the given number of monitors.
    /// A workspace is valid if:
    /// - Its virtual workspace (1-9) is in range
    /// - Its monitor ID exists
    fn is_valid_workspace(workspace_id: WorkspaceId, num_monitors: usize) -> bool {
        if workspace_id <= 0 {
            return false;
        }

        let vspace = Self::virtual_from_workspace(workspace_id);
        if vspace < 1 || vspace > 9 {
            return false;
        }

        // Calculate monitor ID from workspace
        let monitor_id = if workspace_id < 10 {
            0
        } else {
            workspace_id / 10
        };

        (monitor_id as usize) < num_monitors
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
        // Client has monitor field which is Option<MonitorId>
        // MonitorId is i128
        client.monitor.or_else(|| {
            // Fallback: find monitor by workspace
            monitors
                .iter()
                .find(|m| m.active_workspace.id == client.workspace.id)
                .map(|m| m.id)
        })
    }

    async fn move_pinned_windows(&self, virtual_ws: u8) -> Result<()> {
        if self.pinned_patterns.is_empty() {
            return Ok(());
        }

        let clients: Vec<_> = Clients::get_async().await?.into_iter().collect();
        let monitors: Vec<_> = Monitors::get_async().await?.into_iter().collect();

        for client in &clients {
            if !self.is_pinned(client) {
                continue;
            }

            let client_ws_id = client.workspace.id;
            if Self::is_special_workspace(client_ws_id) {
                continue;
            }

            // Find which monitor this client is on
            let monitor_id = match Self::find_monitor_for_client(client, &monitors).await {
                Some(id) => id,
                None => {
                    warn!("Could not determine monitor for pinned client {}", client.address);
                    continue;
                }
            };

            // Calculate target workspace for this monitor
            let target_ws = Self::workspace_id(virtual_ws, monitor_id);

            // Only move if not already there
            if client_ws_id != target_ws {
                debug!(
                    "Moving pinned window {} ({}) from workspace {} to {}",
                    client.class, client.address, client_ws_id, target_ws
                );
                Dispatch::call_async(DispatchType::MoveToWorkspaceSilent(
                    WorkspaceIdentifierWithSpecial::Id(target_ws),
                    Some(WindowIdentifier::Address(client.address.clone())),
                ))
                .await?;
            }
        }

        Ok(())
    }

    pub async fn assign_workspaces(&self) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let monitors: Vec<_> = Monitors::get_async().await?.into_iter().collect();

        if monitors.is_empty() {
            return Err(Error::NoMonitors);
        }

        info!("Assigning workspaces to {} monitor(s)", monitors.len());

        for monitor in &monitors {
            for ws in 1..=9u8 {
                let wsid = Self::workspace_id(ws, monitor.id);
                let is_default = ws == 1;

                let rule = format!(
                    "{wsid},monitor:{},persistent:true,default:{is_default}",
                    monitor.name
                );

                debug!("Setting workspace rule: {rule}");
                Keyword::set_async("workspace", rule).await?;
            }
        }

        self.cleanup_orphan_workspaces().await?;
        self.move_workspaces_to_correct_monitors(&monitors).await?;

        // Determine the target virtual workspace: use the focused monitor's current
        // virtual workspace, falling back to 1 if it's on an invalid workspace
        let focused = Monitor::get_active_async().await?;
        let focused_ws = focused.active_workspace.id;
        let target_virtual = if focused_ws <= 0 || focused_ws % 10 == 0 {
            1u8
        } else {
            Self::virtual_from_workspace(focused_ws)
        };

        // Sync all monitors to the target virtual workspace
        for monitor in &monitors {
            let target_wsid = Self::workspace_id(target_virtual, monitor.id);
            if monitor.active_workspace.id == target_wsid {
                continue;
            }
            debug!("Syncing {} to workspace {target_wsid} (virtual {target_virtual})", monitor.name);
            Dispatch::call_async(DispatchType::Workspace(WorkspaceIdentifierWithSpecial::Id(
                target_wsid,
            )))
            .await?;
        }

        info!("Workspace assignment complete");
        Ok(())
    }

    async fn cleanup_orphan_workspaces(&self) -> Result<()> {
        let clients = Clients::get_async().await?;

        for orphan_id in [0, 10, 20, 30, 40, 50, 60, 70, 80, 90] {
            let target = if orphan_id == 0 { 1 } else { orphan_id + 1 };

            let orphan_clients: Vec<_> = clients
                .iter()
                .filter(|c| c.workspace.id == orphan_id)
                .collect();

            for client in orphan_clients {
                debug!(
                    "Moving client {} from orphan workspace {orphan_id} to {target}",
                    client.address
                );
                Dispatch::call_async(DispatchType::MoveToWorkspaceSilent(
                    WorkspaceIdentifierWithSpecial::Id(target),
                    Some(WindowIdentifier::Address(client.address.clone())),
                ))
                .await?;
            }
        }

        Ok(())
    }

    /// Move workspaces that are on the wrong monitor to their correct one.
    /// This handles the case where monitors were disconnected (all workspaces
    /// collapse to the remaining monitor) and then reconnected.
    async fn move_workspaces_to_correct_monitors(&self, monitors: &[Monitor]) -> Result<()> {
        let workspaces: Vec<_> = Workspaces::get_async().await?.into_iter().collect();

        for ws in &workspaces {
            if ws.id <= 0 {
                continue;
            }

            // Determine which monitor this workspace should be on
            let expected_monitor_id = if ws.id < 10 { 0 } else { ws.id / 10 };

            let expected_monitor = monitors.iter().find(|m| m.id == expected_monitor_id as i128);
            let expected_monitor = match expected_monitor {
                Some(m) => m,
                None => continue, // Monitor doesn't exist, skip
            };

            // Check if it's already on the right monitor
            if ws.monitor == expected_monitor.name {
                continue;
            }

            info!(
                "Moving workspace {} from {} to {}",
                ws.id, ws.monitor, expected_monitor.name
            );
            Dispatch::call_async(DispatchType::MoveWorkspaceToMonitor(
                WorkspaceIdentifier::Id(ws.id),
                MonitorIdentifier::Name(&expected_monitor.name),
            ))
            .await?;
        }

        Ok(())
    }

    pub async fn switch_virtual(&self, virtual_ws: u8) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let focused = Monitor::get_active_async().await?;
        let wsid = Self::workspace_id(virtual_ws, focused.id);

        debug!("Switching to virtual workspace {virtual_ws} (workspace {wsid} on {})", focused.name);

        Dispatch::call_async(DispatchType::Workspace(WorkspaceIdentifierWithSpecial::Id(
            wsid,
        )))
        .await?;

        Ok(())
    }

    /// Sync all monitors to match the workspace that triggered the event.
    /// Called by the event handler when a workspace change is detected.
    pub async fn sync_monitors(&self, trigger_workspace_id: WorkspaceId) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let virtual_ws = Self::virtual_from_workspace(trigger_workspace_id);
        let monitors: Vec<_> = Monitors::get_async().await?.into_iter().collect();

        if monitors.len() <= 1 {
            return Ok(());
        }

        debug!("Syncing monitors to virtual workspace {virtual_ws} (triggered by ws {trigger_workspace_id})");

        // Switch all OTHER monitors to their target workspace
        // Continue on errors to ensure all monitors get synced even if one fails
        for monitor in &monitors {
            let target_wsid = Self::workspace_id(virtual_ws, monitor.id);
            // Skip if this is the trigger workspace or already on target
            if target_wsid == trigger_workspace_id || monitor.active_workspace.id == target_wsid {
                continue;
            }

            debug!("Switching {} to workspace {target_wsid}", monitor.name);
            if let Err(e) = Dispatch::call_async(DispatchType::Workspace(
                WorkspaceIdentifierWithSpecial::Id(target_wsid),
            ))
            .await
            {
                warn!("Failed to switch {} to workspace {target_wsid}: {e}", monitor.name);
            }
        }

        // Move pinned windows
        if let Err(e) = self.move_pinned_windows(virtual_ws).await {
            warn!("Failed to move pinned windows: {e}");
        }

        // Refocus the trigger workspace (restores focus to original monitor)
        // Only if we're not already on it (avoids "Previous workspace doesn't exist" error)
        let active_ws = Workspace::get_active_async().await?;
        if active_ws.id != trigger_workspace_id {
            if let Err(e) = Dispatch::call_async(DispatchType::Workspace(
                WorkspaceIdentifierWithSpecial::Id(trigger_workspace_id),
            ))
            .await
            {
                warn!("Failed to refocus trigger workspace {trigger_workspace_id}: {e}");
            }
        }

        // Focus window under cursor (if any)
        if let Err(e) = self.focus_window_under_cursor(virtual_ws).await {
            warn!("Failed to focus window under cursor: {e}");
        }

        Ok(())
    }

    /// Find and focus the window under the cursor on the current virtual workspace.
    async fn focus_window_under_cursor(&self, virtual_ws: u8) -> Result<()> {
        let cursor = CursorPosition::get_async().await?;
        let clients: Vec<_> = Clients::get_async().await?.into_iter().collect();
        let monitors: Vec<_> = Monitors::get_async().await?.into_iter().collect();

        // Build set of valid workspace IDs for this virtual workspace
        let valid_workspaces: Vec<WorkspaceId> = monitors
            .iter()
            .map(|m| Self::workspace_id(virtual_ws, m.id))
            .collect();

        // Find window on any workspace of this virtual workspace that contains the cursor
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
            Dispatch::call_async(DispatchType::FocusWindow(WindowIdentifier::Address(
                client.address.clone(),
            )))
            .await?;
        }

        Ok(())
    }

    pub async fn move_to_virtual(&self, virtual_ws: u8) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let focused = Monitor::get_active_async().await?;
        let wsid = Self::workspace_id(virtual_ws, focused.id);

        debug!(
            "Moving active window to workspace {wsid} (virtual {virtual_ws})"
        );

        // MoveToWorkspace moves the window AND switches to that workspace
        // The workspace change event will trigger sync_monitors
        Dispatch::call_async(DispatchType::MoveToWorkspace(
            WorkspaceIdentifierWithSpecial::Id(wsid),
            None,
        ))
        .await?;

        Ok(())
    }

    pub async fn navigate(&self, direction: Direction) -> Result<()> {
        let monitors: Vec<_> = Monitors::get_async().await?.into_iter().collect();

        let primary = monitors.iter().find(|m| m.id == 0);

        let current_ws = match primary {
            Some(m) => m.active_workspace.id,
            None => {
                warn!("No primary monitor found");
                return Ok(());
            }
        };

        if Self::is_special_workspace(current_ws) {
            warn!("Primary monitor on special workspace");
            return Ok(());
        }

        let current_virtual = Self::virtual_from_workspace(current_ws);

        let new_virtual = match direction {
            Direction::Next => (current_virtual % 9) + 1,
            Direction::Prev => ((current_virtual + 7) % 9) + 1,
        };

        debug!(
            "Navigating {direction:?}: virtual {current_virtual} -> {new_virtual}"
        );

        self.switch_virtual(new_virtual).await
    }

    pub async fn collapse(&self, mode: CollapseMode) -> Result<()> {
        let _guard = self.ipc_lock.lock().await;

        let active_ws = Workspace::get_active_async().await?;
        let current_ws_id = active_ws.id;

        if Self::is_special_workspace(current_ws_id) {
            return Ok(());
        }

        let virtual_ws = Self::virtual_from_workspace(current_ws_id);
        let clients = Clients::get_async().await?;
        let monitors: Vec<_> = Monitors::get_async().await?.into_iter().collect();
        let num_monitors = monitors.len();

        debug!(
            "Collapsing {:?} to workspace {current_ws_id} (virtual {virtual_ws})",
            mode
        );

        for client in clients.iter() {
            let client_ws_id = client.workspace.id;

            if client_ws_id <= 0 {
                continue;
            }

            let should_move = match mode {
                CollapseMode::All => {
                    // Move all windows from same virtual workspace
                    let client_virtual = Self::virtual_from_workspace(client_ws_id);
                    client_virtual == virtual_ws && client_ws_id != current_ws_id
                }
                CollapseMode::Invisible => {
                    // Only move windows from orphan/invalid workspaces
                    !Self::is_valid_workspace(client_ws_id, num_monitors)
                }
            };

            if should_move {
                debug!(
                    "Moving client {} from workspace {client_ws_id} to {current_ws_id}",
                    client.address
                );
                Dispatch::call_async(DispatchType::MoveToWorkspace(
                    WorkspaceIdentifierWithSpecial::Id(current_ws_id),
                    Some(WindowIdentifier::Address(client.address.clone())),
                ))
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

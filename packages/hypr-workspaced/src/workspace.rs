use std::num::NonZeroU16;

use hyproxide::Instance;
use hyproxide::address::Address;
use hyproxide::dispatch::window::{self, Movement};
use hyproxide::dispatch::{self, Focus, MonitorSelector, rule, workspace};
use hyproxide::monitor::MonitorId;
use hyproxide::query::{self, Client, Monitor};
use hyproxide::workspace::WorkspaceId;
use tracing::{debug, info, warn};

use crate::error::{Error, Result};
use crate::ipc::{CollapseMode, Direction};
use crate::layout::{MonitorLayout, is_valid_workspace};
use crate::virtual_workspace::{MonitorSlot, VirtualWorkspace};
use crate::window::WindowPattern;

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

pub struct WorkspaceManager {
    instance: Instance,
    pinned_patterns: Vec<WindowPattern>,
    layout: MonitorLayout,
}

impl WorkspaceManager {
    pub fn new(instance: Instance) -> Self {
        Self {
            instance,
            pinned_patterns: Vec::new(),
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
                && ws.monitor.as_deref() != Some(&monitor.name)
            {
                warn!(
                    "Workspace {target_wsid} is on {} but belongs on {}, relocating",
                    ws.monitor.as_deref().unwrap_or("no monitor"),
                    monitor.name
                );
                if let Err(e) =
                    dispatch::dispatch(&self.instance, move_workspace(target_wsid, &monitor.name))
                        .await
                {
                    warn!(
                        "Failed to move workspace {target_wsid} to {}: {e}",
                        monitor.name
                    );
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
        if active_ws.workspace.address.id() != Some(trigger_workspace_id)
            && let Err(e) =
                dispatch::dispatch(&self.instance, focus_workspace(trigger_workspace_id)).await
        {
            warn!("Failed to refocus trigger workspace {trigger_workspace_id}: {e}");
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

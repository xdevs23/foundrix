use hyprland::data::{Clients, Monitor, Monitors, Workspace};
use hyprland::dispatch::{Dispatch, DispatchType, MonitorIdentifier, WindowIdentifier, WorkspaceIdentifierWithSpecial};
use hyprland::keyword::Keyword;
use hyprland::shared::{HyprData, HyprDataActive, WorkspaceId};
use tracing::{debug, info, warn};

use crate::error::{Error, Result};
use crate::ipc::Direction;

pub struct WorkspaceManager;

impl WorkspaceManager {
    pub fn new() -> Self {
        Self
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

    pub async fn assign_workspaces(&self) -> Result<()> {
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
                    "{wsid}, monitor:{}, persistent:true, default:{is_default}",
                    monitor.name
                );

                debug!("Setting workspace rule: {rule}");
                Keyword::set_async("workspace", rule).await?;
            }
        }

        self.cleanup_orphan_workspaces().await?;

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

    pub async fn switch_virtual(&self, virtual_ws: u8) -> Result<()> {
        let monitors: Vec<_> = Monitors::get_async().await?.into_iter().collect();

        if monitors.is_empty() {
            return Err(Error::NoMonitors);
        }

        let focused = monitors.iter().find(|m| m.focused);
        let focused_name = focused.map(|m| m.name.clone());

        debug!("Switching to virtual workspace {virtual_ws}");

        if let Some(ref focused_mon) = focused {
            let wsid = Self::workspace_id(virtual_ws, focused_mon.id);
            Dispatch::call_async(DispatchType::Workspace(WorkspaceIdentifierWithSpecial::Id(
                wsid,
            )))
            .await?;
        }

        for monitor in &monitors {
            if focused.is_some() && monitor.focused {
                continue;
            }

            let wsid = Self::workspace_id(virtual_ws, monitor.id);
            Dispatch::call_async(DispatchType::Workspace(WorkspaceIdentifierWithSpecial::Id(
                wsid,
            )))
            .await?;
        }

        if let Some(ref name) = focused_name {
            Dispatch::call_async(DispatchType::FocusMonitor(MonitorIdentifier::Name(name)))
                .await?;
        }

        Ok(())
    }

    pub async fn move_to_virtual(&self, virtual_ws: u8) -> Result<()> {
        let focused = Monitor::get_active_async().await?;
        let wsid = Self::workspace_id(virtual_ws, focused.id);

        debug!(
            "Moving active window to workspace {wsid} (virtual {virtual_ws})"
        );

        Dispatch::call_async(DispatchType::MoveToWorkspace(
            WorkspaceIdentifierWithSpecial::Id(wsid),
            None,
        ))
        .await?;

        self.switch_virtual(virtual_ws).await
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

    pub async fn collapse(&self) -> Result<()> {
        let active_ws = Workspace::get_active_async().await?;
        let current_ws_id = active_ws.id;

        if Self::is_special_workspace(current_ws_id) {
            return Ok(());
        }

        let virtual_ws = Self::virtual_from_workspace(current_ws_id);
        let clients = Clients::get_async().await?;

        debug!(
            "Collapsing virtual workspace {virtual_ws} to workspace {current_ws_id}"
        );

        for client in clients.iter() {
            let client_ws_id = client.workspace.id;

            if client_ws_id <= 0 {
                continue;
            }

            let client_virtual = Self::virtual_from_workspace(client_ws_id);

            if client_virtual == virtual_ws && client_ws_id != current_ws_id {
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

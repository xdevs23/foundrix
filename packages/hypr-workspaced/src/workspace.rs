use hyproxide::Instance;
use hyproxide::address::Address;
use hyproxide::dispatch::window::{self, Movement};
use hyproxide::dispatch::{self, Focus, MonitorSelector, rule, workspace};
use hyproxide::query::{self, Monitor};
use hyproxide::workspace::WorkspaceId;
use tracing::{debug, info, warn};

use crate::error::{Error, Result, SyncFailure, SyncStep};
use crate::ipc::{CollapseMode, Direction};
use crate::layout::MonitorLayout;
use crate::plan::{self, Move, focused_monitor};
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

    /// Move each pinned window to `workspace` on its monitor.
    async fn move_pinned_windows(&self, workspace: VirtualWorkspace) -> Result<()> {
        if self.pinned_patterns.is_empty() {
            return Ok(());
        }

        let clients = query::clients(&self.instance).await?;
        let monitors = query::monitors(&self.instance).await?;
        let moves = plan::follow_pins(
            &clients,
            &monitors,
            &self.layout,
            &self.pinned_patterns,
            workspace,
        )?;
        self.dispatch_moves(moves, false).await
    }

    /// Move each window of `moves`, and follow it with the focus if `follow`.
    async fn dispatch_moves(&self, moves: Vec<Move>, follow: bool) -> Result<()> {
        for Move { window, workspace } in moves {
            debug!("Moving window {window} to workspace {workspace}");
            dispatch::dispatch(&self.instance, move_window(window, workspace, follow)).await?;
        }
        Ok(())
    }

    pub async fn assign_workspaces(&mut self) -> Result<()> {
        let monitors = query::monitors(&self.instance).await?;

        if monitors.is_empty() {
            return Err(Error::NoMonitors);
        }

        info!("Assigning workspaces to {} monitor(s)", monitors.len());

        self.layout = MonitorLayout::assign(&monitors)?;

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

    /// Show `workspace` on every monitor, after Hyprland showed `trigger`,
    /// its workspace on one of them, and keep the focus there. Attempts every
    /// step, and fails with all failed steps when one failed.
    pub async fn sync_monitors(
        &self,
        workspace: VirtualWorkspace,
        trigger: WorkspaceId,
    ) -> Result<()> {
        let monitors = query::monitors(&self.instance).await?;

        if monitors.len() <= 1 {
            return Ok(());
        }

        debug!("Syncing monitors to virtual workspace {workspace} (triggered by ws {trigger})");

        let workspaces = query::workspaces(&self.instance).await?;
        let mut failures = SyncFailures::default();

        for monitor in &monitors {
            let Some(slot) = failures.check(SyncStep::FindSlot, self.layout.slot_of(monitor))
            else {
                continue;
            };
            let target_wsid = workspace.hyprland_id(slot);
            if target_wsid == trigger || monitor.active_workspace.address.id() == Some(target_wsid)
            {
                continue;
            }

            // If the workspace is on the wrong monitor, move it there first
            if let Some(ws) = workspaces
                .iter()
                .find(|w| w.workspace.address.id() == Some(target_wsid))
                && ws.monitor.as_deref() != Some(&monitor.name)
            {
                info!(
                    "Workspace {target_wsid} is on {} but belongs on {}, relocating",
                    ws.monitor.as_deref().unwrap_or("no monitor"),
                    monitor.name
                );
                let moved =
                    dispatch::dispatch(&self.instance, move_workspace(target_wsid, &monitor.name))
                        .await;
                let step = SyncStep::MoveWorkspace {
                    workspace: target_wsid,
                    monitor: monitor.name.clone(),
                };
                failures.record(step, moved);
            }

            debug!("Switching {} to workspace {target_wsid}", monitor.name);
            let shown = dispatch::dispatch(&self.instance, focus_workspace(target_wsid)).await;
            let step = SyncStep::ShowWorkspace {
                workspace: target_wsid,
                monitor: monitor.name.clone(),
            };
            failures.record(step, shown);
        }

        failures.record(
            SyncStep::MovePinnedWindows,
            self.move_pinned_windows(workspace).await,
        );

        let refocus = async {
            let active = query::active_workspace(&self.instance).await?;
            if active.workspace.address.id() != Some(trigger) {
                dispatch::dispatch(&self.instance, focus_workspace(trigger)).await?;
            }
            Ok::<(), hyproxide::Error>(())
        };
        failures.record(SyncStep::Refocus { workspace: trigger }, refocus.await);

        failures.record(
            SyncStep::FocusWindowUnderCursor,
            self.focus_window_under_cursor(workspace).await,
        );

        failures.into_result(workspace)
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

    /// Swap the windows of the current virtual workspace between the focused
    /// monitor and its neighbor in `direction`.
    pub async fn swap_monitor(&self, direction: Direction) -> Result<()> {
        let clients = query::clients(&self.instance).await?;
        let monitors = query::monitors(&self.instance).await?;
        let moves = plan::swap(&clients, &monitors, &self.layout, direction)?;
        debug!("Swapping {direction:?} with {} moves", moves.len());
        self.dispatch_moves(moves, false).await
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
        let clients = query::clients(&self.instance).await?;
        let monitors = query::monitors(&self.instance).await?;
        let moves = plan::collapse(&clients, &monitors, &self.layout, mode)?;
        debug!("Collapsing {mode:?} with {} moves", moves.len());
        self.dispatch_moves(moves, true).await
    }
}

/// The focused monitor.
async fn active_monitor(instance: &Instance) -> Result<Monitor> {
    focused_monitor(&query::monitors(instance).await?).cloned()
}

/// The failed steps of a sync, collected while it attempts every step.
#[derive(Default)]
struct SyncFailures(Vec<SyncFailure>);

impl SyncFailures {
    /// Record the outcome of a step.
    fn record(&mut self, step: SyncStep, outcome: std::result::Result<(), impl Into<Error>>) {
        if let Err(cause) = outcome {
            self.0.push(SyncFailure {
                step,
                cause: cause.into(),
            });
        }
    }

    /// Record the outcome of a step, and return its value when it succeeded.
    fn check<T>(&mut self, step: SyncStep, outcome: Result<T>) -> Option<T> {
        match outcome {
            Ok(value) => Some(value),
            Err(cause) => {
                self.0.push(SyncFailure { step, cause });
                None
            }
        }
    }

    fn into_result(self, workspace: VirtualWorkspace) -> Result<()> {
        if self.0.is_empty() {
            Ok(())
        } else {
            Err(Error::SyncIncomplete {
                workspace,
                failures: self.0,
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn id(number: u32) -> WorkspaceId {
        WorkspaceId::try_from(number).unwrap()
    }

    #[test]
    fn a_sync_succeeds_only_when_every_step_did() {
        let workspace = VirtualWorkspace::new(3).unwrap();
        let mut failures = SyncFailures::default();
        failures.record(SyncStep::MovePinnedWindows, Ok::<(), Error>(()));
        assert_eq!(failures.check(SyncStep::FindSlot, Ok(7)), Some(7));
        assert!(failures.into_result(workspace).is_ok());

        let mut failures = SyncFailures::default();
        let show = SyncStep::ShowWorkspace {
            workspace: id(13),
            monitor: "HEADLESS-2".into(),
        };
        failures.record(show, Err(Error::NoFocusedMonitor));
        failures.record(SyncStep::Refocus { workspace: id(3) }, Ok::<(), Error>(()));
        let no_slot = Err::<(), _>(Error::NoSlot("DP-3".into()));
        assert_eq!(failures.check(SyncStep::FindSlot, no_slot), None);
        let synced = failures.into_result(workspace);
        let Err(Error::SyncIncomplete {
            workspace: failed,
            failures,
        }) = synced
        else {
            panic!("{synced:?}");
        };
        assert_eq!(failed, workspace);
        assert!(matches!(
            failures.as_slice(),
            [
                SyncFailure {
                    step: SyncStep::ShowWorkspace { workspace, .. },
                    cause: Error::NoFocusedMonitor,
                },
                SyncFailure {
                    step: SyncStep::FindSlot,
                    cause: Error::NoSlot(_),
                },
            ] if *workspace == id(13)
        ));
    }
}

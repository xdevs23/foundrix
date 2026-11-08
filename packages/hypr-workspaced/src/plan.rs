//! The windows that `swap`, `collapse` and the pinned windows move, planned
//! from the answers of Hyprland, so the workspace manager only dispatches the
//! moves.

use std::num::NonZeroU16;

use hyproxide::address::Address;
use hyproxide::query::{Client, Monitor, MonitorFlag};
use hyproxide::workspace::WorkspaceId;

use crate::error::{Error, Result};
use crate::ipc::{CollapseMode, Direction};
use crate::layout::MonitorLayout;
use crate::virtual_workspace::VirtualWorkspace;
use crate::window::WindowPattern;

/// A window and the workspace it moves to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Move {
    pub window: Address,
    pub workspace: WorkspaceId,
}

/// The workspace that holds the windows of the focused monitor during a swap,
/// while the windows of the other monitor move in.
const SWAP_BUFFER: NonZeroU16 = NonZeroU16::new(999).unwrap();

/// The focused monitor of the monitors answer.
pub fn focused_monitor(monitors: &[Monitor]) -> Result<&Monitor> {
    monitors
        .iter()
        .find(|monitor| monitor.flags.contains(MonitorFlag::Focused))
        .ok_or(Error::NoFocusedMonitor)
}

/// The virtual workspace a monitor shows, `None` for an orphan workspace.
fn shown_virtual_workspace(monitor: &Monitor) -> Option<VirtualWorkspace> {
    monitor
        .active_workspace
        .address
        .id()
        .and_then(VirtualWorkspace::from_hyprland_id)
}

fn windows_on(clients: &[Client], workspace: WorkspaceId) -> impl Iterator<Item = Address> {
    clients
        .iter()
        .filter(move |client| client.workspace.address.id() == Some(workspace))
        .map(|client| client.address)
}

/// Swap the windows of the virtual workspace on the focused monitor with
/// those on its neighbor in `direction`. Windows move one by one, so each
/// workspace stays on its monitor. Nothing moves when the focused monitor
/// has no neighbor there or shows an orphan workspace.
pub fn swap(
    clients: &[Client],
    monitors: &[Monitor],
    layout: &MonitorLayout,
    direction: Direction,
) -> Result<Vec<Move>> {
    let focused = focused_monitor(monitors)?;
    // The neighbor by position from left to right, the id deciding between
    // monitors above each other.
    let position = |monitor: &&Monitor| (monitor.x, monitor.id);
    let neighbor = match direction {
        Direction::Next => monitors
            .iter()
            .filter(|monitor| position(monitor) > position(&focused))
            .min_by_key(position),
        Direction::Prev => monitors
            .iter()
            .filter(|monitor| position(monitor) < position(&focused))
            .max_by_key(position),
    };
    let (Some(neighbor), Some(workspace)) = (neighbor, shown_virtual_workspace(focused)) else {
        return Ok(Vec::new());
    };

    let here = workspace.hyprland_id(layout.slot_of(focused)?);
    let there = workspace.hyprland_id(layout.slot_of(neighbor)?);
    let to = |workspace: WorkspaceId| move |window: Address| Move { window, workspace };
    Ok(windows_on(clients, here)
        .map(to(SWAP_BUFFER.into()))
        .chain(windows_on(clients, there).map(to(here)))
        .chain(windows_on(clients, here).map(to(there)))
        .collect())
}

/// Move the windows that `mode` names to the workspace of the focused
/// monitor. Nothing moves when it shows an orphan workspace.
pub fn collapse(
    clients: &[Client],
    monitors: &[Monitor],
    layout: &MonitorLayout,
    mode: CollapseMode,
) -> Result<Vec<Move>> {
    let focused = focused_monitor(monitors)?;
    let (Some(target), Some(workspace)) = (
        focused.active_workspace.address.id(),
        shown_virtual_workspace(focused),
    ) else {
        return Ok(Vec::new());
    };

    let collapses = |id: WorkspaceId| match mode {
        CollapseMode::All => {
            id != target && VirtualWorkspace::from_hyprland_id(id) == Some(workspace)
        }
        CollapseMode::Invisible => !layout.has_workspace(id),
    };
    Ok(clients
        .iter()
        .filter(|client| client.workspace.address.id().is_some_and(collapses))
        .map(|client| Move {
            window: client.address,
            workspace: target,
        })
        .collect())
}

/// Move every window that one of `patterns` matches to `workspace` on its
/// monitor.
pub fn follow_pins(
    clients: &[Client],
    monitors: &[Monitor],
    layout: &MonitorLayout,
    patterns: &[WindowPattern],
    workspace: VirtualWorkspace,
) -> Result<Vec<Move>> {
    let pinned = clients
        .iter()
        .filter(|client| patterns.iter().any(|pattern| pattern.matches(client)));

    let mut moves = Vec::new();
    for client in pinned {
        // A window on a special workspace stays there, and a window on no
        // monitor has no monitor to follow.
        let Some(from) = client.workspace.address.id() else {
            continue;
        };
        let Some(monitor) = monitors.iter().find(|monitor| match client.monitor {
            Some(id) => monitor.id == id,
            None => monitor.active_workspace.address.id() == Some(from),
        }) else {
            continue;
        };
        let to = workspace.hyprland_id(layout.slot_of(monitor)?);
        if from != to {
            moves.push(Move {
                window: client.address,
                workspace: to,
            });
        }
    }
    Ok(moves)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::recorded;

    /// The titles of the windows `moves` moves, each with the number of
    /// its new workspace.
    fn titled(moves: &[Move]) -> Vec<(String, u32)> {
        let clients = recorded::clients();
        moves
            .iter()
            .map(|planned| {
                let client = clients
                    .iter()
                    .find(|client| client.address == planned.window)
                    .unwrap();
                (client.title.clone(), planned.workspace.get())
            })
            .collect()
    }

    fn expected(moves: &[(&str, u32)]) -> Vec<(String, u32)> {
        moves
            .iter()
            .map(|&(title, workspace)| (title.to_owned(), workspace))
            .collect()
    }

    /// The moves `plan` makes for the recorded answers, with a layout of
    /// both recorded monitors.
    fn planned(
        plan: impl FnOnce(&[Client], &[Monitor], &MonitorLayout) -> Result<Vec<Move>>,
    ) -> Vec<(String, u32)> {
        let monitors = recorded::monitors();
        let layout = MonitorLayout::of_new_monitors(&monitors);
        titled(&plan(&recorded::clients(), &monitors, &layout).unwrap())
    }

    #[test]
    fn swap_moves_the_windows_through_a_buffer_workspace() {
        let swapped =
            planned(|clients, monitors, layout| swap(clients, monitors, layout, Direction::Next));
        assert_eq!(
            swapped,
            expected(&[
                ("tiled on 3", 999),
                ("fullscreen on 3", 999),
                ("tiled on 13", 3),
                ("floating on 13", 3),
                ("tiled on 3", 13),
                ("fullscreen on 3", 13),
            ])
        );
    }

    #[test]
    fn swap_moves_nothing_without_a_neighbor() {
        let swapped =
            planned(|clients, monitors, layout| swap(clients, monitors, layout, Direction::Prev));
        assert_eq!(swapped, expected(&[]));
    }

    #[test]
    fn collapse_all_pulls_the_same_virtual_workspace() {
        let collapsed = planned(|clients, monitors, layout| {
            collapse(clients, monitors, layout, CollapseMode::All)
        });
        assert_eq!(
            collapsed,
            expected(&[("tiled on 13", 3), ("floating on 13", 3), ("on 23", 3)])
        );
    }

    #[test]
    fn collapse_invisible_pulls_workspaces_without_a_slot() {
        let collapsed = planned(|clients, monitors, layout| {
            collapse(clients, monitors, layout, CollapseMode::Invisible)
        });
        assert_eq!(collapsed, expected(&[("on orphan 10", 3), ("on 23", 3)]));
    }

    fn pins(patterns: &[&str]) -> Vec<WindowPattern> {
        patterns
            .iter()
            .map(|pattern| WindowPattern::parse(pattern).unwrap())
            .collect()
    }

    #[test]
    fn pinned_windows_follow_on_their_monitor() {
        let to = |number| VirtualWorkspace::new(number).unwrap();
        let notes = pins(&["class:notes"]);
        let followed = planned(|clients, monitors, layout| {
            follow_pins(clients, monitors, layout, &notes, to(4))
        });
        assert_eq!(followed, expected(&[("notes on 15", 14)]));

        let stays = planned(|clients, monitors, layout| {
            follow_pins(clients, monitors, layout, &notes, to(5))
        });
        assert_eq!(stays, expected(&[]));

        let foot = pins(&["class:foot"]);
        let followed = planned(|clients, monitors, layout| {
            follow_pins(clients, monitors, layout, &foot, to(3))
        });
        assert_eq!(
            followed,
            expected(&[("on orphan 10", 3), ("on 23", 3), ("on 5", 3)])
        );
    }

    #[test]
    fn a_pinned_window_on_a_monitor_without_a_slot_fails() {
        let monitors = recorded::monitors();
        let layout = MonitorLayout::of_new_monitors(&monitors[..1]);
        let followed = follow_pins(
            &recorded::clients(),
            &monitors,
            &layout,
            &pins(&["class:notes"]),
            VirtualWorkspace::new(4).unwrap(),
        );
        assert!(
            matches!(&followed, Err(Error::NoSlot(name)) if name == "HYPR-WORKSPACED-1"),
            "{followed:?}"
        );
    }
}

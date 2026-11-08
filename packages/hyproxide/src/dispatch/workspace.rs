//! The `hl.dsp.workspace.*` dispatchers.

use super::table_dispatcher;
use super::{Dispatcher, MonitorSelector, WorkspaceSelector};
use crate::lua::{Table, Value};
use crate::workspace::WorkspaceId;

table_dispatcher! {
    /// Set the shown name of a workspace, or reset it without a name.
    Rename = "hl.dsp.workspace.rename" { name: String }
}

pub fn rename(workspace: impl Into<WorkspaceSelector>) -> Rename {
    Rename(Table::new().with("workspace", workspace.into()))
}

/// Give a numbered workspace another number.
#[must_use]
pub fn change_id(workspace: impl Into<WorkspaceSelector>, id: WorkspaceId) -> Dispatcher {
    let table = Table::new()
        .with("workspace", workspace.into())
        .with("id", id.get());
    Dispatcher::with_argument("hl.dsp.workspace.change_id", table)
}

table_dispatcher! {
    /// Move a workspace to a monitor: the active workspace of the focused
    /// monitor unless `workspace` selects another.
    MoveToMonitor = "hl.dsp.workspace.move" { workspace: WorkspaceSelector }
}

pub fn move_to_monitor(monitor: impl Into<MonitorSelector>) -> MoveToMonitor {
    MoveToMonitor(Table::new().with("monitor", monitor.into()))
}

/// Swap the active workspaces of two monitors.
#[must_use]
pub fn swap_monitors(first: MonitorSelector, second: MonitorSelector) -> Dispatcher {
    let table = Table::new()
        .with("monitor1", first)
        .with("monitor2", second);
    Dispatcher::with_argument("hl.dsp.workspace.swap_monitors", table)
}

/// Show or hide a special workspace on the focused monitor, by the part of
/// its address after `special:`. Without a name it is the workspace
/// `special:special`.
#[must_use]
pub fn toggle_special(name: Option<&str>) -> Dispatcher {
    let arguments = name.map(Value::from).into_iter().collect();
    Dispatcher::call("hl.dsp.workspace.toggle_special", arguments)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dispatch::{WorkspaceName, lua};

    fn id(number: u32) -> WorkspaceId {
        WorkspaceId::try_from(number).unwrap()
    }

    #[test]
    fn renames() {
        assert_eq!(
            lua(rename(id(3)).name("mail")),
            r#"hl.dsp.workspace.rename({ workspace = "3", name = "mail" })"#
        );
        assert_eq!(
            lua(rename(WorkspaceSelector::Named(
                WorkspaceName::try_from("web").unwrap()
            ))),
            r#"hl.dsp.workspace.rename({ workspace = "name:web" })"#
        );
        assert_eq!(
            lua(change_id(id(3), id(13))),
            r#"hl.dsp.workspace.change_id({ workspace = "3", id = 13 })"#
        );
    }

    #[test]
    fn monitors() {
        assert_eq!(
            lua(move_to_monitor(MonitorSelector::Name("DP-1".into())).workspace(id(14))),
            r#"hl.dsp.workspace.move({ monitor = "DP-1", workspace = "14" })"#
        );
        assert_eq!(
            lua(move_to_monitor(MonitorSelector::Current)),
            r#"hl.dsp.workspace.move({ monitor = "current" })"#
        );
        assert_eq!(
            lua(swap_monitors(
                MonitorSelector::Current,
                MonitorSelector::Offset(1)
            )),
            r#"hl.dsp.workspace.swap_monitors({ monitor1 = "current", monitor2 = "+1" })"#
        );
    }

    #[test]
    fn special_workspaces() {
        assert_eq!(
            lua(toggle_special(Some("scratch"))),
            r#"hl.dsp.workspace.toggle_special("scratch")"#
        );
        assert_eq!(
            lua(toggle_special(None)),
            "hl.dsp.workspace.toggle_special()"
        );
    }
}

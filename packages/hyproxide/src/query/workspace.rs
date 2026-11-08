//! The `workspaces`, `activeworkspace` and `workspacerules` answers.

use serde::Deserialize;

use super::wire;
use crate::address::Address;
use crate::monitor::MonitorId;
use crate::workspace::WorkspaceRef;

/// An entry of the `workspaces` answer, or the `activeworkspace` answer.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Workspace {
    #[serde(flatten, deserialize_with = "wire::workspace")]
    pub workspace: WorkspaceRef,
    /// The name of the monitor that shows the workspace.
    #[serde(deserialize_with = "wire::question_mark_as_none")]
    pub monitor: Option<String>,
    #[serde(rename = "monitorID", deserialize_with = "wire::null_as_no_monitor")]
    pub monitor_id: Option<MonitorId>,
    /// The number of windows.
    pub windows: u32,
    #[serde(rename = "hasfullscreen")]
    pub has_fullscreen: bool,
    /// The window focused last on the workspace.
    #[serde(rename = "lastwindow", deserialize_with = "wire::optional_address")]
    pub last_window: Option<Address>,
    #[serde(rename = "lastwindowtitle")]
    pub last_window_title: String,
    #[serde(rename = "ispersistent")]
    pub is_persistent: bool,
    /// The name of the tiling layout, if Hyprland has one for it.
    #[serde(rename = "tiledLayout", deserialize_with = "wire::unknown_as_none")]
    pub tiled_layout: Option<String>,
}

/// An entry of the `workspacerules` answer. Fields the rule does not set are
/// `None`.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceRule {
    /// The workspace selector the rule applies to.
    pub workspace_string: String,
    pub enabled: bool,
    pub monitor: Option<String>,
    pub default: Option<bool>,
    pub persistent: Option<bool>,
    pub gaps_in: Option<Gaps>,
    pub gaps_out: Option<Gaps>,
    pub border_size: Option<i64>,
    pub border: Option<bool>,
    pub rounding: Option<bool>,
    pub decorate: Option<bool>,
    pub shadow: Option<bool>,
    pub default_name: Option<String>,
    /// The command run when the workspace is created empty.
    pub on_created_empty: Option<String>,
}

/// Gaps along the four edges of a window.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(from = "[i64; 4]")]
pub struct Gaps {
    pub top: i64,
    pub right: i64,
    pub bottom: i64,
    pub left: i64,
}

impl From<[i64; 4]> for Gaps {
    fn from([top, right, bottom, left]: [i64; 4]) -> Self {
        Self {
            top,
            right,
            bottom,
            left,
        }
    }
}

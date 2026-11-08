//! The parts of Hyprland's JSON answers read by the daemon.
//!
//! Each type lists only the fields the daemon uses, so fields that Hyprland
//! adds or reshapes elsewhere in an answer do not break deserialization.
//! Hyprland 0.57 sends a workspace id only for a normal workspace: a special
//! workspace and the missing workspace of a disabled monitor come without one.

use hyprland::data::FullscreenMode;
use hyprland::shared::{Address, MonitorId, WorkspaceId};
use serde::Deserialize;

/// A workspace named inside another answer.
#[derive(Debug, Clone, Deserialize)]
pub struct WorkspaceRef {
    pub id: Option<WorkspaceId>,
}

/// An entry of the `monitors` answer.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Monitor {
    pub id: MonitorId,
    pub name: String,
    pub description: String,
    pub x: i32,
    pub active_workspace: WorkspaceRef,
    pub focused: bool,
}

/// An entry of the `clients` answer: one window.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Client {
    pub address: Address,
    pub at: (i16, i16),
    pub size: (i16, i16),
    pub workspace: WorkspaceRef,
    pub floating: bool,
    pub fullscreen: FullscreenMode,
    pub monitor: Option<MonitorId>,
    pub class: String,
    pub initial_class: String,
    pub title: String,
    pub initial_title: String,
    pub pid: i32,
}

/// An entry of the `workspaces` answer, or the `activeworkspace` answer.
#[derive(Debug, Clone, Deserialize)]
pub struct Workspace {
    pub id: Option<WorkspaceId>,
    pub monitor: String,
}

/// The `cursorpos` answer.
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct CursorPosition {
    pub x: i64,
    pub y: i64,
}

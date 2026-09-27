use std::io;
use thiserror::Error;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Error)]
pub enum Error {
    #[error("Hyprland IPC error: {0}")]
    Hyprland(#[from] hyprland::error::HyprError),

    #[error("Hyprland answered {answer:?} to {request:?}")]
    HyprlandRequest { request: String, answer: String },

    #[error("Hyprland socket not found: {0}")]
    HyprlandSocket(&'static str),

    #[error("Hyprland's request queue stayed full for the whole wait of {0:?}")]
    HyprlandQueueFull(std::time::Duration),

    #[error("Hyprland's answer to {request:?} could not be read: {source}")]
    HyprlandAnswer {
        request: &'static str,
        source: serde_json::Error,
    },

    #[error("Hyprland lists no focused monitor")]
    NoFocusedMonitor,

    #[error("IO error: {0}")]
    Io(#[from] io::Error),

    #[error("Invalid command: {0}")]
    InvalidCommand(String),

    #[error("Invalid virtual workspace: {0} (must be 1-9)")]
    InvalidVirtualWorkspace(u8),

    #[error("Invalid window pattern: {0}")]
    InvalidWindowPattern(String),

    #[error("Daemon not running or socket not found")]
    DaemonNotRunning,

    #[error("No monitors found")]
    NoMonitors,

    #[error("{0}")]
    Other(String),
}

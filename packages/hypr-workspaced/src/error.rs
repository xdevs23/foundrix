use std::io;
use thiserror::Error;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Error)]
pub enum Error {
    #[error("Hyprland IPC error: {0}")]
    Hyprland(#[from] hyprland::error::HyprError),

    #[error("IO error: {0}")]
    Io(#[from] io::Error),

    #[error("Invalid command: {0}")]
    InvalidCommand(String),

    #[error("Invalid virtual workspace: {0} (must be 1-9)")]
    InvalidVirtualWorkspace(u8),

    #[error("Daemon not running or socket not found")]
    DaemonNotRunning,

    #[error("No monitors found")]
    NoMonitors,

    #[error("{0}")]
    Other(String),
}

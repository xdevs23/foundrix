use std::io;
use std::path::PathBuf;

use thiserror::Error;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Error)]
pub enum Error {
    #[error(transparent)]
    Hyprland(#[from] hyproxide::Error),

    #[error("Hyprland lists no focused monitor")]
    NoFocusedMonitor,

    #[error("IO error: {0}")]
    Io(#[from] io::Error),

    #[error("Invalid command: {0}")]
    InvalidCommand(String),

    #[error("Invalid virtual workspace: {0:?} (must be 1-9)")]
    InvalidVirtualWorkspace(String),

    #[error("Invalid window pattern: {0}")]
    InvalidWindowPattern(String),

    #[error("Daemon not running or socket not found")]
    DaemonNotRunning,

    #[error("No monitors found")]
    NoMonitors,

    #[error(
        "Monitor {0} has no slot: it was connected after the daemon assigned the workspaces, \
         or 256 monitors have slots already. Run `hypr-workspaced assign`."
    )]
    NoSlot(String),

    #[error(
        "Neither XDG_STATE_HOME nor HOME is an absolute path, so the monitor registry has no \
         place. Start the daemon with HOME set."
    )]
    NoStateDirectory,

    #[error("Reading the monitor registry {} failed: {source}", path.display())]
    ReadRegistry {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("Writing the monitor registry {} failed: {source}", path.display())]
    WriteRegistry {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("RUST_LOG does not read as a log filter: {0}")]
    LogFilter(#[source] tracing_subscriber::filter::FromEnvError),

    #[error("{0}")]
    Other(String),
}

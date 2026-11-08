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

    #[error("Invalid command: {0}")]
    InvalidCommand(String),

    #[error("Invalid virtual workspace: {0:?} (must be 1-9)")]
    InvalidVirtualWorkspace(String),

    #[error("Invalid window pattern: {0}")]
    InvalidWindowPattern(String),

    #[error("No daemon listens on {}: start it with `hypr-workspaced daemon`", path.display())]
    DaemonNotRunning { path: PathBuf },

    #[error("Connecting to the daemon at {} failed: {source}", path.display())]
    ConnectToDaemon {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error("Sending the command to the daemon or reading its answer failed: {0}")]
    TalkToDaemon(#[source] io::Error),

    #[error("The daemon could not run the command: {0}")]
    CommandFailed(String),

    #[error("The daemon answered {0:?}, which its protocol does not have")]
    InvalidResponse(String),

    #[error("Listening for commands on {} failed: {source}", path.display())]
    Listen {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

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

    #[error("Changing the log level failed: {0}")]
    LogLevel(#[source] tracing_subscriber::reload::Error),
}

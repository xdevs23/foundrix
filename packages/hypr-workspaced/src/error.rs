use std::fmt::{self, Display, Formatter};
use std::io;
use std::path::PathBuf;

use hyproxide::workspace::WorkspaceId;
use thiserror::Error;

use crate::virtual_workspace::VirtualWorkspace;

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

    #[error(
        "Virtual workspace {workspace} is not shown on every monitor: {}",
        list(failures)
    )]
    SyncIncomplete {
        workspace: VirtualWorkspace,
        failures: Vec<SyncFailure>,
    },
}

/// A step of a workspace sync that failed, with its cause.
#[derive(Debug)]
pub struct SyncFailure {
    pub step: SyncStep,
    pub cause: Error,
}

/// A step of a workspace sync.
#[derive(Debug)]
pub enum SyncStep {
    /// Finding the slot of a monitor, which the cause names.
    FindSlot,
    MoveWorkspace {
        workspace: WorkspaceId,
        monitor: String,
    },
    ShowWorkspace {
        workspace: WorkspaceId,
        monitor: String,
    },
    MovePinnedWindows,
    /// Focusing the workspace again that the sync started from.
    Refocus {
        workspace: WorkspaceId,
    },
    FocusWindowUnderCursor,
}

impl Display for SyncFailure {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        let cause = &self.cause;
        match &self.step {
            SyncStep::FindSlot => write!(f, "{cause}"),
            SyncStep::MoveWorkspace { workspace, monitor } => {
                write!(
                    f,
                    "moving workspace {workspace} to {monitor} failed: {cause}"
                )
            }
            SyncStep::ShowWorkspace { workspace, monitor } => {
                write!(
                    f,
                    "showing workspace {workspace} on {monitor} failed: {cause}"
                )
            }
            SyncStep::MovePinnedWindows => write!(f, "moving the pinned windows failed: {cause}"),
            SyncStep::Refocus { workspace } => {
                write!(f, "focusing workspace {workspace} again failed: {cause}")
            }
            SyncStep::FocusWindowUnderCursor => {
                write!(f, "focusing the window under the cursor failed: {cause}")
            }
        }
    }
}

/// The failed steps of a sync, one after the other.
fn list(failures: &[SyncFailure]) -> String {
    failures
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join("; ")
}

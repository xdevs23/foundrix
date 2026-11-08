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

/// The failed steps of a sync, collected while it attempts every step.
#[derive(Default)]
pub struct SyncFailures(Vec<SyncFailure>);

impl SyncFailures {
    /// Record the outcome of a step.
    pub fn record(&mut self, step: SyncStep, outcome: std::result::Result<(), impl Into<Error>>) {
        if let Err(cause) = outcome {
            self.0.push(SyncFailure {
                step,
                cause: cause.into(),
            });
        }
    }

    /// Record the outcome of a step, and return its value when it succeeded.
    pub fn check<T>(&mut self, step: SyncStep, outcome: Result<T>) -> Option<T> {
        match outcome {
            Ok(value) => Some(value),
            Err(cause) => {
                self.0.push(SyncFailure { step, cause });
                None
            }
        }
    }

    pub fn into_result(self, workspace: VirtualWorkspace) -> Result<()> {
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

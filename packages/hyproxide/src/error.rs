use std::fmt::{self, Display, Formatter};
use std::io;
use std::path::PathBuf;
use std::string::FromUtf8Error;

pub type Result<T> = std::result::Result<T, Error>;

/// What went wrong while talking to Hyprland, one variant per operation.
/// Every message ends with what a person can do about it.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error(
        "{variable} is not set, so no Hyprland instance is known. {}",
        NextStep::RunInsideHyprland
    )]
    NoInstance { variable: &'static str },

    #[error("connecting to the Hyprland socket {} failed. {}", path.display(), NextStep::CheckHyprlandRuns)]
    Connect {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error(
        "sending {request:?} to Hyprland or reading its answer failed. {}",
        NextStep::CheckHyprlandRuns
    )]
    Exchange {
        request: String,
        #[source]
        source: io::Error,
    },

    #[error(
        "Hyprland closed its event socket {}. {}",
        path.display(),
        NextStep::SubscribeAgain
    )]
    EventsClosed { path: PathBuf },

    #[error("reading events from the Hyprland socket {} failed. {}", path.display(), NextStep::SubscribeAgain)]
    ReadEvents {
        path: PathBuf,
        #[source]
        source: io::Error,
    },

    #[error(
        "the answer from Hyprland to {request:?} is not UTF-8 text. {}",
        NextStep::CloseWindowWithBrokenText
    )]
    NotUtf8 {
        request: String,
        #[source]
        source: FromUtf8Error,
    },

    #[error(
        "Hyprland returned {answer:?} for {request:?}. {}",
        NextStep::ReadTheAnswer
    )]
    Refused { request: String, answer: String },

    #[error(
        "the answer from Hyprland to {request:?} does not have the form read by this library: {answer:?}. {}",
        NextStep::CheckTheVersion
    )]
    Answer {
        request: String,
        answer: String,
        #[source]
        source: serde_json::Error,
    },
}

/// What a person can do about a failure, written once for every message of
/// the crate that needs it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum NextStep {
    RunInsideHyprland,
    CheckHyprlandRuns,
    SubscribeAgain,
    CloseWindowWithBrokenText,
    ReadTheAnswer,
    CheckTheVersion,
    UseOneWord,
    UseAWorkspaceNumber,
    UseAWorkspaceName,
}

impl Display for NextStep {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            NextStep::RunInsideHyprland => {
                "Run the program inside a Hyprland session, or set XDG_RUNTIME_DIR and \
                 HYPRLAND_INSTANCE_SIGNATURE to the values of a running Hyprland."
            }
            NextStep::CheckHyprlandRuns => {
                "Check that this Hyprland instance still runs: Hyprland removes its socket when \
                 it exits."
            }
            // Hyprland drops a client once 64 events wait to be written to it
            // (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/ipc/s2/Unix.cpp>,
            // checked 2026-11-08).
            NextStep::SubscribeAgain => {
                "Check that this Hyprland instance still runs, then subscribe again and read its \
                 state anew: Hyprland replays no event, and it also closes the socket of a \
                 program that falls 64 events behind."
            }
            NextStep::CloseWindowWithBrokenText => {
                "Close the window whose title or class has bytes that are not UTF-8, the usual \
                 cause, and report the request to the developers of the program."
            }
            NextStep::ReadTheAnswer => {
                "The answer gives the cause: correct the request, or bring Hyprland into the \
                 state the request needs."
            }
            NextStep::CheckTheVersion => {
                "Check that Hyprland 0.57 runs (`hyprctl version`), and report the answer to the \
                 developers of the program if it does."
            }
            NextStep::UseOneWord => {
                "Hyprland splits plain requests at spaces: use a name without whitespace or \
                 control characters."
            }
            NextStep::UseAWorkspaceNumber => "Use a workspace number from 1 to 2147483647.",
            NextStep::UseAWorkspaceName => {
                "Use a workspace name that is not empty and not a number, or select a numbered \
                 workspace by its number."
            }
        })
    }
}

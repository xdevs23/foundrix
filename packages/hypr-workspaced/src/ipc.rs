use std::fmt::{self, Display, Formatter};
use std::path::PathBuf;
use std::str::FromStr;

use clap::ValueEnum;
use clap::builder::PossibleValue;

use crate::error::{Error, Result};
use crate::virtual_workspace::VirtualWorkspace;

/// Which neighbor a command means: the next virtual workspace or the
/// monitor to the right, or the previous one or the monitor to the left.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum Direction {
    /// The next virtual workspace, or the monitor to the right
    Next,
    /// The previous virtual workspace, or the monitor to the left
    Prev,
}

/// Which windows `collapse` moves to the focused monitor.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum CollapseMode {
    /// The windows of the same virtual workspace on the other monitors
    All,
    /// The windows on workspaces no monitor shows
    Invisible,
}

/// Whether the daemon logs at the debug level.
#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub enum DebugLogging {
    On,
    Off,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    Switch(VirtualWorkspace),
    MoveTo(VirtualWorkspace),
    Navigate(Direction),
    Collapse(CollapseMode),
    Swap(Direction),
    Assign,
    Pin(String),
    Unpin(String),
    Pins,
    Debug(DebugLogging),
}

/// How `value` is written on the command line and in the protocol.
fn spelling(value: &impl ValueEnum) -> PossibleValue {
    value
        .to_possible_value()
        .unwrap_or_else(|| unreachable!("no value is skipped"))
}

/// The value of a closed set that `word` writes, as [`spelling`] writes it.
fn named<T: ValueEnum>(word: &str) -> Option<T> {
    T::from_str(word, false).ok()
}

impl FromStr for Command {
    type Err = Error;

    fn from_str(s: &str) -> Result<Self> {
        let invalid = || Error::InvalidCommand(s.to_owned());
        let words: Vec<&str> = s.split_whitespace().collect();

        match words.as_slice() {
            ["switch", workspace] => Ok(Command::Switch(workspace.parse()?)),
            ["move", workspace] => Ok(Command::MoveTo(workspace.parse()?)),
            ["next"] => Ok(Command::Navigate(Direction::Next)),
            ["prev"] => Ok(Command::Navigate(Direction::Prev)),
            ["collapse", mode] => named(mode).map(Command::Collapse).ok_or_else(invalid),
            ["swap", direction] => named(direction).map(Command::Swap).ok_or_else(invalid),
            ["assign"] => Ok(Command::Assign),
            ["pin", pattern @ ..] if !pattern.is_empty() => Ok(Command::Pin(pattern.join(" "))),
            ["unpin", pattern @ ..] if !pattern.is_empty() => Ok(Command::Unpin(pattern.join(" "))),
            ["pins"] => Ok(Command::Pins),
            ["debug", logging] => named(logging).map(Command::Debug).ok_or_else(invalid),
            _ => Err(invalid()),
        }
    }
}

impl Display for Command {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Command::Switch(workspace) => write!(f, "switch {workspace}"),
            Command::MoveTo(workspace) => write!(f, "move {workspace}"),
            Command::Navigate(Direction::Next) => write!(f, "next"),
            Command::Navigate(Direction::Prev) => write!(f, "prev"),
            Command::Collapse(mode) => write!(f, "collapse {}", spelling(mode).get_name()),
            Command::Swap(direction) => write!(f, "swap {}", spelling(direction).get_name()),
            Command::Assign => write!(f, "assign"),
            Command::Pin(pattern) => write!(f, "pin {pattern}"),
            Command::Unpin(pattern) => write!(f, "unpin {pattern}"),
            Command::Pins => write!(f, "pins"),
            Command::Debug(logging) => write!(f, "debug {}", spelling(logging).get_name()),
        }
    }
}

/// The socket of the daemon, in the runtime directory of the session, which
/// only its user can reach.
pub fn socket_path() -> Result<PathBuf> {
    Ok(hyproxide::runtime_directory()?.join("hypr-workspaced.sock"))
}

#[derive(Debug)]
pub enum Response {
    Ok,
    Data(String),
    Error(String),
}

impl FromStr for Response {
    type Err = Error;

    fn from_str(s: &str) -> Result<Self> {
        let trimmed = s.trim();
        if trimmed == "ok" {
            Ok(Response::Ok)
        } else if let Some(msg) = trimmed.strip_prefix("error: ") {
            Ok(Response::Error(msg.to_string()))
        } else if let Some(data) = trimmed.strip_prefix("data: ") {
            Ok(Response::Data(data.to_string()))
        } else {
            Err(Error::InvalidResponse(s.to_owned()))
        }
    }
}

impl std::fmt::Display for Response {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Response::Ok => write!(f, "ok"),
            Response::Data(data) => write!(f, "data: {data}"),
            Response::Error(msg) => write!(f, "error: {msg}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn workspace(number: &str) -> VirtualWorkspace {
        number.parse().unwrap()
    }

    #[test]
    fn parse_commands() {
        assert_eq!(
            "switch 3".parse::<Command>().unwrap(),
            Command::Switch(workspace("3"))
        );
        assert_eq!(
            "move 5".parse::<Command>().unwrap(),
            Command::MoveTo(workspace("5"))
        );
        assert_eq!(
            "next".parse::<Command>().unwrap(),
            Command::Navigate(Direction::Next)
        );
        assert_eq!(
            "prev".parse::<Command>().unwrap(),
            Command::Navigate(Direction::Prev)
        );
        assert_eq!(
            "collapse all".parse::<Command>().unwrap(),
            Command::Collapse(CollapseMode::All)
        );
        assert_eq!(
            "collapse invisible".parse::<Command>().unwrap(),
            Command::Collapse(CollapseMode::Invisible)
        );
        assert_eq!(
            "swap prev".parse::<Command>().unwrap(),
            Command::Swap(Direction::Prev)
        );
        assert_eq!(
            "debug off".parse::<Command>().unwrap(),
            Command::Debug(DebugLogging::Off)
        );
        assert_eq!("assign".parse::<Command>().unwrap(), Command::Assign);
    }

    #[test]
    fn invalid_commands() {
        for invalid in [
            "switch 0",
            "switch 10",
            "switch three",
            "move 0",
            "collapse some",
            "swap up",
            "debug true",
        ] {
            assert!(invalid.parse::<Command>().is_err(), "{invalid}");
        }
    }

    #[test]
    fn responses_read_their_three_forms_and_nothing_else() {
        assert!(matches!("ok\n".parse(), Ok(Response::Ok)));
        assert!(matches!("data: a\n".parse(), Ok(Response::Data(data)) if data == "a"));
        assert!(matches!("error: b\n".parse(), Ok(Response::Error(message)) if message == "b"));
        assert!(matches!(
            "".parse::<Response>(),
            Err(Error::InvalidResponse(response)) if response.is_empty()
        ));
    }

    #[test]
    fn roundtrip() {
        for command in [
            Command::Switch(workspace("5")),
            Command::MoveTo(workspace("9")),
            Command::Navigate(Direction::Prev),
            Command::Collapse(CollapseMode::Invisible),
            Command::Swap(Direction::Next),
            Command::Pin("class:foot".into()),
            Command::Debug(DebugLogging::On),
        ] {
            assert_eq!(command.to_string().parse::<Command>().unwrap(), command);
        }
    }
}

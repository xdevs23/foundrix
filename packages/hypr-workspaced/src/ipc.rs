use std::env;
use std::path::PathBuf;
use std::str::FromStr;

use crate::error::{Error, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    Next,
    Prev,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    Switch(u8),
    MoveTo(u8),
    Navigate(Direction),
    Collapse,
    Assign,
}

impl Command {
    pub fn validate_workspace(ws: u8) -> Result<u8> {
        if (1..=9).contains(&ws) {
            Ok(ws)
        } else {
            Err(Error::InvalidVirtualWorkspace(ws))
        }
    }
}

impl FromStr for Command {
    type Err = Error;

    fn from_str(s: &str) -> Result<Self> {
        let parts: Vec<&str> = s.trim().split_whitespace().collect();

        match parts.as_slice() {
            ["switch", n] => {
                let ws = n.parse::<u8>().map_err(|_| Error::InvalidCommand(s.to_string()))?;
                Ok(Command::Switch(Command::validate_workspace(ws)?))
            }
            ["move", n] => {
                let ws = n.parse::<u8>().map_err(|_| Error::InvalidCommand(s.to_string()))?;
                Ok(Command::MoveTo(Command::validate_workspace(ws)?))
            }
            ["next"] => Ok(Command::Navigate(Direction::Next)),
            ["prev"] => Ok(Command::Navigate(Direction::Prev)),
            ["collapse"] => Ok(Command::Collapse),
            ["assign"] => Ok(Command::Assign),
            _ => Err(Error::InvalidCommand(s.to_string())),
        }
    }
}

impl std::fmt::Display for Command {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Command::Switch(ws) => write!(f, "switch {ws}"),
            Command::MoveTo(ws) => write!(f, "move {ws}"),
            Command::Navigate(Direction::Next) => write!(f, "next"),
            Command::Navigate(Direction::Prev) => write!(f, "prev"),
            Command::Collapse => write!(f, "collapse"),
            Command::Assign => write!(f, "assign"),
        }
    }
}

pub fn socket_path() -> PathBuf {
    let runtime_dir = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
    PathBuf::from(runtime_dir).join("hypr-workspaced.sock")
}

#[derive(Debug)]
pub enum Response {
    Ok,
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
        } else {
            Err(Error::InvalidCommand(format!("Invalid response: {s}")))
        }
    }
}

impl std::fmt::Display for Response {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Response::Ok => write!(f, "ok"),
            Response::Error(msg) => write!(f, "error: {msg}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_commands() {
        assert_eq!("switch 3".parse::<Command>().unwrap(), Command::Switch(3));
        assert_eq!("move 5".parse::<Command>().unwrap(), Command::MoveTo(5));
        assert_eq!(
            "next".parse::<Command>().unwrap(),
            Command::Navigate(Direction::Next)
        );
        assert_eq!(
            "prev".parse::<Command>().unwrap(),
            Command::Navigate(Direction::Prev)
        );
        assert_eq!("collapse".parse::<Command>().unwrap(), Command::Collapse);
        assert_eq!("assign".parse::<Command>().unwrap(), Command::Assign);
    }

    #[test]
    fn invalid_workspace() {
        assert!("switch 0".parse::<Command>().is_err());
        assert!("switch 10".parse::<Command>().is_err());
        assert!("move 0".parse::<Command>().is_err());
    }

    #[test]
    fn roundtrip() {
        let cmd = Command::Switch(5);
        assert_eq!(cmd.to_string().parse::<Command>().unwrap(), cmd);
    }
}

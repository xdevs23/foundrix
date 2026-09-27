//! Hyprland state, read with the JSON forms of hyprctl's requests.
//!
//! Each query goes through the request module's [`exchange`], so it waits for
//! room in Hyprland's request queue like every command does. The answers are
//! deserialized into the hyprland crate's data types.

use hyprland::data::{Client, CursorPosition, Monitor, Workspace};

use crate::error::{Error, Result};
use crate::request::exchange;

/// All monitors, disabled ones included.
const MONITORS: &str = "monitors all";
const CLIENTS: &str = "clients";
const WORKSPACES: &str = "workspaces";
const ACTIVE_WORKSPACE: &str = "activeworkspace";
const CURSOR_POSITION: &str = "cursorpos";

pub async fn monitors() -> Result<Vec<Monitor>> {
    decode(
        MONITORS,
        serde_json::from_str(&exchange("j", MONITORS).await?),
    )
}

/// The focused monitor.
pub async fn active_monitor() -> Result<Monitor> {
    focused(monitors().await?)
}

/// All windows.
pub async fn clients() -> Result<Vec<Client>> {
    decode(
        CLIENTS,
        serde_json::from_str(&exchange("j", CLIENTS).await?),
    )
}

pub async fn workspaces() -> Result<Vec<Workspace>> {
    decode(
        WORKSPACES,
        serde_json::from_str(&exchange("j", WORKSPACES).await?),
    )
}

/// The workspace of the focused monitor.
pub async fn active_workspace() -> Result<Workspace> {
    decode(
        ACTIVE_WORKSPACE,
        serde_json::from_str(&exchange("j", ACTIVE_WORKSPACE).await?),
    )
}

pub async fn cursor_position() -> Result<CursorPosition> {
    decode(
        CURSOR_POSITION,
        serde_json::from_str(&exchange("j", CURSOR_POSITION).await?),
    )
}

/// Attach the request to an answer that did not deserialize.
fn decode<T>(request: &'static str, answer: serde_json::Result<T>) -> Result<T> {
    answer.map_err(|source| Error::HyprlandAnswer { request, source })
}

fn focused(monitors: Vec<Monitor>) -> Result<Monitor> {
    monitors
        .into_iter()
        .find(|monitor| monitor.focused)
        .ok_or(Error::NoFocusedMonitor)
}

#[cfg(test)]
mod tests {
    //! The answers under `testdata/hyprland-answers` were recorded from a
    //! headless Hyprland 0.56.2 session with one terminal window titled
    //! "terminal".

    use super::*;

    macro_rules! recorded {
        ($file:literal) => {
            include_str!(concat!("../testdata/hyprland-answers/", $file))
        };
    }

    fn recorded_monitors() -> Vec<Monitor> {
        decode(
            MONITORS,
            serde_json::from_str(recorded!("monitors-all.json")),
        )
        .unwrap()
    }

    #[test]
    fn monitors_answer() {
        let monitors = recorded_monitors();
        assert_eq!(monitors.len(), 1);
        assert_eq!(monitors[0].name, "Virtual-1");
        assert_eq!(monitors[0].active_workspace.id, 1);
        assert!(monitors[0].focused);
        assert!(!monitors[0].disabled);
    }

    #[test]
    fn active_monitor_is_the_focused_entry() {
        assert_eq!(focused(recorded_monitors()).unwrap().name, "Virtual-1");
    }

    #[test]
    fn no_focused_monitor_is_an_error() {
        let mut monitors = recorded_monitors();
        monitors[0].focused = false;
        assert!(matches!(focused(monitors), Err(Error::NoFocusedMonitor)));
        assert!(matches!(focused(Vec::new()), Err(Error::NoFocusedMonitor)));
    }

    #[test]
    fn clients_answer() {
        let clients: Vec<Client> =
            decode(CLIENTS, serde_json::from_str(recorded!("clients.json"))).unwrap();
        assert_eq!(clients.len(), 1);
        assert_eq!(clients[0].title, "terminal");
        assert_eq!(clients[0].address.to_string(), "0x647fc1065230");
        assert_eq!(clients[0].workspace.id, 1);
        assert_eq!(clients[0].monitor, Some(0));
        assert_eq!((clients[0].at, clients[0].size), ((21, 21), (470, 342)));
    }

    #[test]
    fn workspaces_answer() {
        let workspaces: Vec<Workspace> = decode(
            WORKSPACES,
            serde_json::from_str(recorded!("workspaces.json")),
        )
        .unwrap();
        assert_eq!(workspaces.len(), 1);
        assert_eq!(workspaces[0].id, 1);
        assert_eq!(workspaces[0].monitor, "Virtual-1");
    }

    #[test]
    fn active_workspace_answer() {
        let workspace: Workspace = decode(
            ACTIVE_WORKSPACE,
            serde_json::from_str(recorded!("activeworkspace.json")),
        )
        .unwrap();
        assert_eq!(workspace.id, 1);
        assert_eq!(workspace.last_window_title, "terminal");
    }

    #[test]
    fn cursor_position_answer() {
        let cursor: CursorPosition = decode(
            CURSOR_POSITION,
            serde_json::from_str(recorded!("cursorpos.json")),
        )
        .unwrap();
        assert_eq!((cursor.x, cursor.y), (256, 192));
    }

    #[test]
    fn unreadable_answer_names_the_request() {
        let result: Result<Vec<Monitor>> =
            decode(MONITORS, serde_json::from_str("unknown request"));
        assert!(
            matches!(
                result,
                Err(Error::HyprlandAnswer {
                    request: "monitors all",
                    ..
                })
            ),
            "{result:?}"
        );
    }
}

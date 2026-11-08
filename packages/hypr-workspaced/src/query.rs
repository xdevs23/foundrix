//! Hyprland state, read with the JSON forms of hyprctl's requests.
//!
//! Each query goes through the request module's [`exchange`], so it waits for
//! room in Hyprland's request queue like every command does. The answers are
//! deserialized into the types of the answer module.

use crate::answer::{Client, CursorPosition, Monitor, Workspace};
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
    //! headless Hyprland 0.57.1 session with one terminal window titled
    //! "terminal". The files with "special" in their name were recorded after
    //! that window moved to the special workspace "special:scratch" and a
    //! second output, HEADLESS-2, was disabled.

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
        assert_eq!(monitors[0].active_workspace.id, Some(1));
        assert!(monitors[0].focused);
    }

    #[test]
    fn disabled_monitor_has_no_active_workspace() {
        let monitors: Vec<Monitor> = decode(
            MONITORS,
            serde_json::from_str(recorded!("monitors-all-special-and-disabled.json")),
        )
        .unwrap();
        let ids: Vec<_> = monitors
            .iter()
            .map(|m| (m.name.as_str(), m.active_workspace.id))
            .collect();
        assert_eq!(ids, [("Virtual-1", Some(3)), ("HEADLESS-2", None)]);
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
        assert_eq!(clients[0].address.to_string(), "0x573106b0db30");
        assert_eq!(clients[0].workspace.id, Some(1));
        assert_eq!(clients[0].monitor, Some(0));
        assert_eq!((clients[0].at, clients[0].size), ((0, 0), (2048, 1080)));
    }

    #[test]
    fn window_on_a_special_workspace_has_no_workspace_id() {
        let clients: Vec<Client> = decode(
            CLIENTS,
            serde_json::from_str(recorded!("clients-on-special.json")),
        )
        .unwrap();
        assert_eq!(clients.len(), 1);
        assert_eq!(clients[0].workspace.id, None);
    }

    #[test]
    fn special_workspace_has_no_id() {
        let workspaces: Vec<Workspace> = decode(
            WORKSPACES,
            serde_json::from_str(recorded!("workspaces-with-special.json")),
        )
        .unwrap();
        let ids: Vec<_> = workspaces.iter().map(|w| w.id).collect();
        assert_eq!(ids.len(), 10);
        assert_eq!(ids.iter().filter(|id| id.is_none()).count(), 1);
    }

    #[test]
    fn workspaces_answer() {
        let workspaces: Vec<Workspace> = decode(
            WORKSPACES,
            serde_json::from_str(recorded!("workspaces.json")),
        )
        .unwrap();
        assert_eq!(workspaces.len(), 1);
        assert_eq!(workspaces[0].id, Some(1));
        assert_eq!(workspaces[0].monitor, "Virtual-1");
    }

    #[test]
    fn active_workspace_answer() {
        let workspace: Workspace = decode(
            ACTIVE_WORKSPACE,
            serde_json::from_str(recorded!("activeworkspace.json")),
        )
        .unwrap();
        assert_eq!(workspace.id, Some(1));
        assert_eq!(workspace.monitor, "Virtual-1");
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

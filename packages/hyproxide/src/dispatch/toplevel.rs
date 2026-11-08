//! The dispatchers at the top of `hl.dsp`.

use std::time::Duration;

use super::table_dispatcher;
use super::{Action, Direction, Dispatcher, MonitorSelector, WindowSelector, WorkspaceSelector};
use crate::keyboard::{Modifier, Modifiers};
use crate::lua::{Table, Value};
use crate::monitor::MonitorId;

/// Run a shell command.
///
/// `hl.dsp.exec_cmd` also takes a table of window rules for the window the
/// command opens. This builder does not type that table: write such a call
/// with [`Dispatcher::lua`].
#[must_use]
pub fn exec_cmd(command: &str) -> Dispatcher {
    Dispatcher::with_argument("hl.dsp.exec_cmd", command)
}

/// Run a command without a shell and without the environment of
/// `exec_cmd`.
#[must_use]
pub fn exec_raw(command: &str) -> Dispatcher {
    Dispatcher::with_argument("hl.dsp.exec_raw", command)
}

/// Quit Hyprland.
#[must_use]
pub fn exit() -> Dispatcher {
    Dispatcher::call("hl.dsp.exit", Vec::new())
}

#[must_use]
pub fn reload_config() -> Dispatcher {
    Dispatcher::call("hl.dsp.reload_config", Vec::new())
}

/// Enter a submap of binds, or leave every submap with `reset`.
#[must_use]
pub fn submap(name: &str) -> Dispatcher {
    Dispatcher::with_argument("hl.dsp.submap", name)
}

/// The modifier names separated by spaces, as the Lua of Hyprland reads them.
impl From<Modifiers> for Value {
    fn from(modifiers: Modifiers) -> Self {
        let names: Vec<_> = modifiers.iter().map(Modifier::name).collect();
        Value::String(names.join(" "))
    }
}

/// Pass the key of the running bind on to a window.
#[must_use]
pub fn pass(window: impl Into<WindowSelector>) -> Dispatcher {
    Dispatcher::with_argument("hl.dsp.pass", Table::new().with("window", window.into()))
}

table_dispatcher! {
    /// Send a key press and release to the focused window, or to another one.
    SendShortcut = "hl.dsp.send_shortcut" { window: WindowSelector }
}

/// `key` is a key name such as `Return`, `code:<keycode>` or
/// `mouse:<button>`.
pub fn send_shortcut(modifiers: Modifiers, key: &str) -> SendShortcut {
    SendShortcut(Table::new().with("mods", modifiers).with("key", key))
}

/// The state `send_key_state` puts a key in.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyState {
    Down,
    Up,
    Repeat,
}

impl From<KeyState> for Value {
    fn from(state: KeyState) -> Self {
        Value::from(match state {
            KeyState::Down => "down",
            KeyState::Up => "up",
            KeyState::Repeat => "repeat",
        })
    }
}

table_dispatcher! {
    /// Send one key state to the focused window, or to another one.
    SendKeyState = "hl.dsp.send_key_state" { window: WindowSelector }
}

/// `key` is named as for [`send_shortcut`].
pub fn send_key_state(modifiers: Modifiers, key: &str, state: KeyState) -> SendKeyState {
    let table = Table::new()
        .with("mods", modifiers)
        .with("key", key)
        .with("state", state);
    SendKeyState(table)
}

/// Send a message to the layout of the focused workspace, such as
/// `togglesplit`.
#[must_use]
pub fn layout(message: &str) -> Dispatcher {
    Dispatcher::with_argument("hl.dsp.layout", message)
}

table_dispatcher! {
    /// Switch monitors on or off: every enabled monitor, or the one given to
    /// [`Dpms::monitor`].
    Dpms = "hl.dsp.dpms" { action: Action }
}

pub fn dpms() -> Dpms {
    Dpms(Table::new())
}

impl Dpms {
    /// Switch only this monitor.
    ///
    /// Hyprland 0.57.1 switches every enabled monitor when the selector of
    /// `dpms` matches none, and returns `ok`
    /// (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/config/lua/bindings/LuaBindingsDispatchers.cpp>,
    /// checked 2026-11-08). A [`MonitorId`] comes only from an answer or an
    /// event of Hyprland, so it matches a monitor unless that monitor went
    /// away since.
    pub fn monitor(self, monitor: MonitorId) -> Self {
        Self(self.0.with("monitor", MonitorSelector::Id(monitor)))
    }
}

/// Send a `custom` event with the text to every client of the event socket.
#[must_use]
pub fn event(data: &str) -> Dispatcher {
    Dispatcher::with_argument("hl.dsp.event", data)
}

/// Trigger a global shortcut that an application registered.
#[must_use]
pub fn global(app_id: &str, name: &str) -> Dispatcher {
    Dispatcher::with_argument("hl.dsp.global", format!("{app_id}:{name}"))
}

#[must_use]
pub fn force_renderer_reload() -> Dispatcher {
    Dispatcher::call("hl.dsp.force_renderer_reload", Vec::new())
}

/// Report the session as idle after `idle` without input, in place of the
/// timers of idle clients.
#[must_use]
pub fn force_idle(idle: Duration) -> Dispatcher {
    Dispatcher::with_argument("hl.dsp.force_idle", idle.as_secs_f64())
}

/// End the input capture of a remote desktop session.
#[must_use]
pub fn release_input_capture() -> Dispatcher {
    Dispatcher::call("hl.dsp.release_input_capture", Vec::new())
}

/// Do nothing, for a bind that only blocks its key.
#[must_use]
pub fn no_op() -> Dispatcher {
    Dispatcher::call("hl.dsp.no_op", Vec::new())
}

/// What `hl.dsp.focus` focuses.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Focus {
    /// The window in a direction.
    Direction(Direction),
    Monitor(MonitorSelector),
    /// A workspace on the monitor that shows it, or on the focused monitor if
    /// `on_current_monitor`.
    Workspace {
        workspace: WorkspaceSelector,
        on_current_monitor: bool,
    },
    Window(WindowSelector),
    /// The urgent window, or else the window focused before the current one.
    UrgentOrLast,
    /// The window focused before the current one.
    Last,
}

impl From<Focus> for Dispatcher {
    fn from(focus: Focus) -> Self {
        let table = Table::new();
        let table = match focus {
            Focus::Direction(direction) => table.with("direction", direction),
            Focus::Monitor(monitor) => table.with("monitor", monitor),
            Focus::Workspace {
                workspace,
                on_current_monitor,
            } => table
                .with("workspace", workspace)
                .with("on_current_monitor", on_current_monitor),
            Focus::Window(window) => table.with("window", window),
            Focus::UrgentOrLast => table.with("urgent_or_last", true),
            Focus::Last => table.with("last", true),
        };
        Dispatcher::with_argument("hl.dsp.focus", table)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dispatch::lua;
    use crate::workspace::WorkspaceId;

    #[test]
    fn processes_and_session() {
        assert_eq!(
            lua(exec_cmd("foot -e \"top\"")),
            r#"hl.dsp.exec_cmd("foot -e \"top\"")"#
        );
        assert_eq!(lua(exec_raw("foot")), r#"hl.dsp.exec_raw("foot")"#);
        assert_eq!(lua(exit()), "hl.dsp.exit()");
        assert_eq!(lua(reload_config()), "hl.dsp.reload_config()");
        assert_eq!(
            lua(force_renderer_reload()),
            "hl.dsp.force_renderer_reload()"
        );
        assert_eq!(
            lua(force_idle(Duration::from_millis(1500))),
            "hl.dsp.force_idle(1.5)"
        );
        assert_eq!(
            lua(release_input_capture()),
            "hl.dsp.release_input_capture()"
        );
        assert_eq!(lua(no_op()), "hl.dsp.no_op()");
        assert_eq!(
            lua(layout("togglesplit")),
            r#"hl.dsp.layout("togglesplit")"#
        );
        assert_eq!(
            lua(event("hello, world")),
            r#"hl.dsp.event("hello, world")"#
        );
        assert_eq!(
            lua(global("org.example.app", "record")),
            r#"hl.dsp.global("org.example.app:record")"#
        );
        assert_eq!(lua(dpms()), "hl.dsp.dpms({})");
        assert_eq!(
            lua(dpms().action(Action::Disable).monitor(MonitorId::new(2))),
            r#"hl.dsp.dpms({ action = "disable", monitor = "2" })"#
        );
    }

    #[test]
    fn modifiers_are_names_for_lua() {
        let modifiers: Modifiers = [Modifier::Super, Modifier::Ctrl].into_iter().collect();
        assert_eq!(Value::from(modifiers).to_string(), r#""CTRL SUPER""#);
    }

    #[test]
    fn keys() {
        assert_eq!(lua(submap("resize")), r#"hl.dsp.submap("resize")"#);
        assert_eq!(
            lua(pass(WindowSelector::Class("^obs$".into()))),
            r#"hl.dsp.pass({ window = "class:^obs$" })"#
        );
        let modifiers = [Modifier::Super, Modifier::Shift].into_iter().collect();
        assert_eq!(
            lua(send_shortcut(modifiers, "Return").window(WindowSelector::Active)),
            r#"hl.dsp.send_shortcut({ mods = "SHIFT SUPER", key = "Return", window = "active" })"#
        );
        assert_eq!(
            lua(send_key_state(
                Modifiers::default(),
                "code:36",
                KeyState::Down
            )),
            r#"hl.dsp.send_key_state({ mods = "", key = "code:36", state = "down" })"#
        );
    }

    #[test]
    fn focus() {
        assert_eq!(
            lua(Focus::Direction(Direction::Left)),
            r#"hl.dsp.focus({ direction = "left" })"#
        );
        assert_eq!(
            lua(Focus::Monitor(MonitorSelector::Offset(-1))),
            r#"hl.dsp.focus({ monitor = "-1" })"#
        );
        assert_eq!(
            lua(Focus::Workspace {
                workspace: WorkspaceId::try_from(13).unwrap().into(),
                on_current_monitor: false
            }),
            r#"hl.dsp.focus({ workspace = "13", on_current_monitor = false })"#
        );
        assert_eq!(
            lua(Focus::Window(WindowSelector::Tag("mail".into()))),
            r#"hl.dsp.focus({ window = "tag:mail" })"#
        );
        assert_eq!(
            lua(Focus::UrgentOrLast),
            "hl.dsp.focus({ urgent_or_last = true })"
        );
        assert_eq!(lua(Focus::Last), "hl.dsp.focus({ last = true })");
    }
}

//! The values dispatchers take to name windows, workspaces and monitors, and
//! the small choices many dispatchers share.

use std::num::NonZeroU32;

use crate::address::Address;
use crate::lua::Value;
use crate::monitor::MonitorId;
use crate::window::StableId;
use crate::workspace::{SPECIAL, WorkspaceAddress, WorkspaceId, WorkspaceName};

/// A direction on screen.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    Left,
    Right,
    Up,
    Down,
}

impl From<Direction> for Value {
    fn from(direction: Direction) -> Self {
        Value::from(match direction {
            Direction::Left => "left",
            Direction::Right => "right",
            Direction::Up => "up",
            Direction::Down => "down",
        })
    }
}

/// What a dispatcher that switches something does with it. A dispatcher
/// given none toggles.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    Toggle,
    Enable,
    Disable,
}

impl From<Action> for Value {
    fn from(action: Action) -> Self {
        Value::from(match action {
            Action::Toggle => "toggle",
            Action::Enable => "enable",
            Action::Disable => "disable",
        })
    }
}

/// Which window a dispatcher acts on. The patterns are RE2 regular
/// expressions that must match the whole text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WindowSelector {
    /// The focused window.
    Active,
    /// The first floating window on the workspace of the focused window.
    Floating,
    /// The first tiled window on the workspace of the focused window.
    Tiled,
    Class(String),
    InitialClass(String),
    Title(String),
    InitialTitle(String),
    /// A window with a tag that matches the pattern.
    Tag(String),
    StableId(StableId),
    Address(Address),
    Pid(i32),
}

impl From<WindowSelector> for Value {
    fn from(selector: WindowSelector) -> Self {
        Value::String(match selector {
            WindowSelector::Active => "active".to_owned(),
            WindowSelector::Floating => "floating".to_owned(),
            WindowSelector::Tiled => "tiled".to_owned(),
            WindowSelector::Class(pattern) => format!("class:{pattern}"),
            WindowSelector::InitialClass(pattern) => format!("initialclass:{pattern}"),
            WindowSelector::Title(pattern) => format!("title:{pattern}"),
            WindowSelector::InitialTitle(pattern) => format!("initialtitle:{pattern}"),
            WindowSelector::Tag(pattern) => format!("tag:{pattern}"),
            WindowSelector::StableId(id) => format!("stableid:{id}"),
            WindowSelector::Address(address) => format!("address:{address}"),
            WindowSelector::Pid(pid) => format!("pid:{pid}"),
        })
    }
}

impl From<Address> for WindowSelector {
    fn from(address: Address) -> Self {
        WindowSelector::Address(address)
    }
}

/// Which workspace a dispatcher acts on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WorkspaceSelector {
    Id(WorkspaceId),
    /// A named workspace, by its address.
    Named(WorkspaceName),
    /// A special workspace, by the part of its address after `special:`.
    Special(String),
    /// The first numbered workspace without windows.
    Empty {
        /// Skip workspaces bound to other monitors by a workspace rule.
        on_monitor: bool,
        /// Start after the active workspace of the focused monitor.
        after_active: bool,
    },
    /// The workspace that was active before the current one.
    Previous,
    /// The workspace that was active on the focused monitor before the
    /// current one.
    PreviousOnMonitor,
    /// The numbered workspace after the active one.
    Next,
    /// A numbered workspace counted from the active one.
    Offset(i32),
    /// A workspace counted from the active one among the workspaces the
    /// focused monitor can show, open or not.
    MonitorOffset(i32),
    /// The workspace at a position, from 1, among the workspaces the focused
    /// monitor can show, open or not.
    MonitorPosition(NonZeroU32),
    /// An open workspace counted from the active one.
    OpenOffset {
        scope: MonitorScope,
        offset: i32,
    },
    /// The open workspace at a position, from 1.
    OpenPosition {
        scope: MonitorScope,
        position: NonZeroU32,
    },
}

impl WorkspaceSelector {
    /// The selector of a workspace read from an answer or an event, `None`
    /// when there is no workspace.
    #[must_use]
    pub fn of(workspace: &WorkspaceAddress) -> Option<Self> {
        match workspace {
            WorkspaceAddress::Numbered(id) => Some(Self::Id(*id)),
            WorkspaceAddress::Named(name) => Some(Self::Named(name.clone())),
            WorkspaceAddress::Special(name) => Some(Self::Special(name.clone())),
            WorkspaceAddress::None => None,
        }
    }
}

impl From<WorkspaceSelector> for Value {
    fn from(selector: WorkspaceSelector) -> Self {
        Value::String(match selector {
            WorkspaceSelector::Id(id) => id.to_string(),
            WorkspaceSelector::Named(name) => format!("name:{name}"),
            WorkspaceSelector::Special(name) => format!("{SPECIAL}{name}"),
            WorkspaceSelector::Empty {
                on_monitor,
                after_active,
            } => {
                let on_monitor = if on_monitor { "m" } else { "" };
                let after_active = if after_active { "n" } else { "" };
                format!("empty{on_monitor}{after_active}")
            }
            WorkspaceSelector::Previous => "previous".to_owned(),
            WorkspaceSelector::PreviousOnMonitor => "previous_per_monitor".to_owned(),
            WorkspaceSelector::Next => "next".to_owned(),
            WorkspaceSelector::Offset(offset) => format!("{offset:+}"),
            WorkspaceSelector::MonitorOffset(offset) => format!("r{offset:+}"),
            WorkspaceSelector::MonitorPosition(position) => format!("r~{position}"),
            WorkspaceSelector::OpenOffset { scope, offset } => {
                format!("{}{offset:+}", scope.letter())
            }
            WorkspaceSelector::OpenPosition { scope, position } => {
                format!("{}~{position}", scope.letter())
            }
        })
    }
}

impl From<WorkspaceId> for WorkspaceSelector {
    fn from(id: WorkspaceId) -> Self {
        WorkspaceSelector::Id(id)
    }
}

/// The monitors among whose open workspaces a selector counts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MonitorScope {
    Focused,
    All,
}

impl MonitorScope {
    /// The letter that starts the selector.
    fn letter(self) -> char {
        match self {
            MonitorScope::Focused => 'm',
            MonitorScope::All => 'e',
        }
    }
}

/// Which monitor a dispatcher acts on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MonitorSelector {
    /// The focused monitor.
    Current,
    /// The monitor next to the focused one in a direction.
    Direction(Direction),
    /// A monitor counted from the focused one, wrapping around.
    Offset(i32),
    Id(MonitorId),
    Name(String),
    /// The monitor whose description starts with the text.
    Description(String),
}

impl From<MonitorSelector> for Value {
    fn from(selector: MonitorSelector) -> Self {
        match selector {
            MonitorSelector::Current => Value::from("current"),
            MonitorSelector::Direction(direction) => Value::from(direction),
            MonitorSelector::Offset(offset) => Value::String(format!("{offset:+}")),
            MonitorSelector::Id(id) => Value::String(id.to_string()),
            MonitorSelector::Name(name) => Value::String(name),
            MonitorSelector::Description(description) => {
                Value::String(format!("desc:{description}"))
            }
        }
    }
}

impl From<MonitorId> for MonitorSelector {
    fn from(id: MonitorId) -> Self {
        MonitorSelector::Id(id)
    }
}

#[cfg(test)]
mod tests;

//! The `hl.dsp.window.*` dispatchers. Each acts on the focused window unless
//! its `window` method selects another.

use super::table_dispatcher;
use super::{Action, Direction, Dispatcher, MonitorSelector, WindowSelector, WorkspaceSelector};
use crate::lua::{Table, Value};
use crate::window::FullscreenState;

table_dispatcher! {
    /// Ask a window to close.
    Close = "hl.dsp.window.close" { window: WindowSelector }
}

pub fn close() -> Close {
    Close(Table::new())
}

table_dispatcher! {
    /// Kill the process of a window.
    Kill = "hl.dsp.window.kill" { window: WindowSelector }
}

pub fn kill() -> Kill {
    Kill(Table::new())
}

table_dispatcher! {
    /// Send a signal to the process of a window.
    Signal = "hl.dsp.window.signal" { window: WindowSelector }
}

pub fn signal(signal: i32) -> Signal {
    Signal(Table::new().with("signal", signal))
}

table_dispatcher! {
    /// Make a window float or tile.
    Float = "hl.dsp.window.float" { action: Action, window: WindowSelector }
}

pub fn float() -> Float {
    Float(Table::new())
}

table_dispatcher! {
    /// Switch pseudo-tiling of a window.
    Pseudo = "hl.dsp.window.pseudo" { action: Action, window: WindowSelector }
}

pub fn pseudo() -> Pseudo {
    Pseudo(Table::new())
}

table_dispatcher! {
    /// Pin a floating window, so it shows on every workspace.
    Pin = "hl.dsp.window.pin" { action: Action, window: WindowSelector }
}

pub fn pin() -> Pin {
    Pin(Table::new())
}

/// How a window covers its monitor when made fullscreen.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FullscreenMode {
    Fullscreen,
    Maximized,
}

impl From<FullscreenMode> for Value {
    fn from(mode: FullscreenMode) -> Self {
        Value::from(match mode {
            FullscreenMode::Fullscreen => "fullscreen",
            FullscreenMode::Maximized => "maximized",
        })
    }
}

/// What the fullscreen dispatchers do with the state they name. Without one,
/// `fullscreen` toggles and `fullscreen_state` sets.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FullscreenAction {
    Toggle,
    Set,
    Unset,
}

impl From<FullscreenAction> for Value {
    fn from(action: FullscreenAction) -> Self {
        Value::from(match action {
            FullscreenAction::Toggle => "toggle",
            FullscreenAction::Set => "set",
            FullscreenAction::Unset => "unset",
        })
    }
}

table_dispatcher! {
    /// Make a window fullscreen or maximized. Without a mode it is made
    /// fullscreen.
    Fullscreen = "hl.dsp.window.fullscreen" {
        mode: FullscreenMode,
        action: FullscreenAction,
        layout_aware: bool,
        window: WindowSelector,
    }
}

pub fn fullscreen() -> Fullscreen {
    Fullscreen(Table::new())
}

impl From<FullscreenState> for Value {
    fn from(state: FullscreenState) -> Self {
        Value::from(u32::from(state.number()))
    }
}

table_dispatcher! {
    /// Set the fullscreen state Hyprland tracks for a window and the one the
    /// window is told, apart from each other.
    FullscreenStates = "hl.dsp.window.fullscreen_state" {
        action: FullscreenAction,
        layout_aware: bool,
        window: WindowSelector,
    }
}

pub fn fullscreen_state(internal: FullscreenState, client: FullscreenState) -> FullscreenStates {
    FullscreenStates(
        Table::new()
            .with("internal", internal)
            .with("client", client),
    )
}

/// Where `hl.dsp.window.move` takes a window.
#[derive(Debug, Clone, PartialEq)]
pub enum Movement {
    /// To the next place in a direction, with its group if `group_aware`.
    Direction {
        direction: Direction,
        group_aware: bool,
    },
    /// To a position on the layout, or by an amount if `relative`.
    Position { x: f64, y: f64, relative: bool },
    Workspace {
        workspace: WorkspaceSelector,
        follow: bool,
    },
    /// To the active workspace of a monitor.
    Monitor {
        monitor: MonitorSelector,
        follow: bool,
    },
    /// Into the group in a direction.
    IntoGroup(Direction),
    /// Into the group in a direction, or into a new group with the window
    /// there.
    IntoOrCreateGroup(Direction),
    /// Out of its group, towards a direction if one is given.
    OutOfGroup(Option<Direction>),
}

impl From<Movement> for Table {
    fn from(movement: Movement) -> Self {
        let table = Table::new();
        match movement {
            Movement::Direction {
                direction,
                group_aware,
            } => table
                .with("direction", direction)
                .with("group_aware", group_aware),
            Movement::Position { x, y, relative } => {
                table.with("x", x).with("y", y).with("relative", relative)
            }
            Movement::Workspace { workspace, follow } => {
                table.with("workspace", workspace).with("follow", follow)
            }
            Movement::Monitor { monitor, follow } => {
                table.with("monitor", monitor).with("follow", follow)
            }
            Movement::IntoGroup(direction) => table.with("into_group", direction),
            Movement::IntoOrCreateGroup(direction) => table.with("into_or_create_group", direction),
            Movement::OutOfGroup(Some(direction)) => table.with("out_of_group", direction),
            Movement::OutOfGroup(None) => table.with("out_of_group", true),
        }
    }
}

table_dispatcher! {
    /// Move a window.
    Move = "hl.dsp.window.move" { window: WindowSelector }
}

pub fn move_window(movement: Movement) -> Move {
    Move(movement.into())
}

/// Which window `hl.dsp.window.swap` swaps a window with.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Swap {
    /// The window in a direction.
    Direction(Direction),
    With(WindowSelector),
    /// The next window in the layout.
    Next,
    /// The previous window in the layout.
    Previous,
}

impl From<Swap> for Table {
    fn from(swap: Swap) -> Self {
        let table = Table::new();
        match swap {
            Swap::Direction(direction) => table.with("direction", direction),
            Swap::With(other) => table.with("target", other),
            Swap::Next => table.with("next", true),
            Swap::Previous => table.with("prev", true),
        }
    }
}

table_dispatcher! {
    /// Swap a window with another one.
    SwapWith = "hl.dsp.window.swap" { window: WindowSelector }
}

pub fn swap(swap: Swap) -> SwapWith {
    SwapWith(swap.into())
}

table_dispatcher! {
    /// Center a floating window on its monitor.
    Center = "hl.dsp.window.center" { window: WindowSelector }
}

pub fn center() -> Center {
    Center(Table::new())
}

table_dispatcher! {
    /// Focus the next window on the workspace, or the previous one when
    /// `next` is false, only among tiled or floating windows when one of
    /// those is set.
    CycleNext = "hl.dsp.window.cycle_next" {
        next: bool,
        tiled: bool,
        floating: bool,
        window: WindowSelector,
    }
}

pub fn cycle_next() -> CycleNext {
    CycleNext(Table::new())
}

table_dispatcher! {
    /// Toggle a tag on a window, or add or remove it with a leading `+` or
    /// `-`.
    Tag = "hl.dsp.window.tag" { window: WindowSelector }
}

pub fn tag(tag: impl Into<String>) -> Tag {
    Tag(Table::new().with("tag", tag.into()))
}

table_dispatcher! {
    /// Remove all tags of a window.
    ClearTags = "hl.dsp.window.clear_tags" { window: WindowSelector }
}

pub fn clear_tags() -> ClearTags {
    ClearTags(Table::new())
}

/// Swallow the focused window into the window that started it, or let it go.
#[must_use]
pub fn toggle_swallow() -> Dispatcher {
    Dispatcher::call("hl.dsp.window.toggle_swallow", Vec::new())
}

/// Raise the focused window above the other floating windows.
#[must_use]
pub fn bring_to_top() -> Dispatcher {
    Dispatcher::call("hl.dsp.window.bring_to_top", Vec::new())
}

/// Where among the floating windows `alter_zorder` puts a window.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ZOrder {
    Top,
    Bottom,
}

impl From<ZOrder> for Value {
    fn from(order: ZOrder) -> Self {
        Value::from(match order {
            ZOrder::Top => "top",
            ZOrder::Bottom => "bottom",
        })
    }
}

table_dispatcher! {
    /// Raise or lower a floating window.
    AlterZOrder = "hl.dsp.window.alter_zorder" { window: WindowSelector }
}

pub fn alter_zorder(mode: ZOrder) -> AlterZOrder {
    AlterZOrder(Table::new().with("mode", mode))
}

table_dispatcher! {
    /// Set a property of a window, as a window rule would.
    SetProp = "hl.dsp.window.set_prop" { window: WindowSelector }
}

pub fn set_prop(prop: impl Into<String>, value: impl Into<String>) -> SetProp {
    SetProp(
        Table::new()
            .with("prop", prop.into())
            .with("value", value.into()),
    )
}

table_dispatcher! {
    /// Exclude the focused window from groups.
    DenyFromGroup = "hl.dsp.window.deny_from_group" { action: Action }
}

pub fn deny_from_group() -> DenyFromGroup {
    DenyFromGroup(Table::new())
}

/// Move the focused window with the mouse, for a bind on a mouse button.
#[must_use]
pub fn drag() -> Dispatcher {
    Dispatcher::call("hl.dsp.window.drag", Vec::new())
}

table_dispatcher! {
    /// Resize a window to a size, or by an amount if `relative`.
    Resize = "hl.dsp.window.resize" { relative: bool, window: WindowSelector }
}

pub fn resize(x: f64, y: f64) -> Resize {
    Resize(Table::new().with("x", x).with("y", y))
}

/// Resize the focused window with the mouse, for a bind on a mouse button.
/// Without `keep_aspect_ratio` the configuration sets it.
#[must_use]
pub fn mouse_resize(keep_aspect_ratio: Option<bool>) -> Dispatcher {
    let arguments = keep_aspect_ratio
        .map(|keep| Table::new().with("keep_aspect_ratio", keep).into())
        .into_iter()
        .collect();
    Dispatcher::call("hl.dsp.window.resize", arguments)
}

#[cfg(test)]
mod tests;

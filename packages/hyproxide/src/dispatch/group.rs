//! The `hl.dsp.group.*` dispatchers. Each acts on the group of the focused
//! window unless its `window` method selects another window.

use std::num::NonZeroU32;

use super::table_dispatcher;
use super::{Action, WindowSelector};
use crate::lua::Table;

table_dispatcher! {
    /// Make a window a group, or dissolve its group.
    Toggle = "hl.dsp.group.toggle" { window: WindowSelector }
}

pub fn toggle() -> Toggle {
    Toggle(Table::new())
}

table_dispatcher! {
    /// Show the next window of a group.
    Next = "hl.dsp.group.next" { window: WindowSelector }
}

pub fn next() -> Next {
    Next(Table::new())
}

table_dispatcher! {
    /// Show the previous window of a group.
    Prev = "hl.dsp.group.prev" { window: WindowSelector }
}

pub fn prev() -> Prev {
    Prev(Table::new())
}

table_dispatcher! {
    /// Show the window at a position, from 1, of a group.
    Active = "hl.dsp.group.active" { window: WindowSelector }
}

pub fn active(position: NonZeroU32) -> Active {
    Active(Table::new().with("index", position.get()))
}

table_dispatcher! {
    /// Move the shown window of the focused group one place forward, or
    /// backward when `forward` is false.
    MoveWindow = "hl.dsp.group.move_window" { forward: bool }
}

pub fn move_window() -> MoveWindow {
    MoveWindow(Table::new())
}

table_dispatcher! {
    /// Lock a group, so windows cannot join or leave it.
    Lock = "hl.dsp.group.lock" { action: Action, window: WindowSelector }
}

pub fn lock() -> Lock {
    Lock(Table::new())
}

table_dispatcher! {
    /// Lock all groups.
    LockAll = "hl.dsp.group.lock" { action: Action }
}

pub fn lock_all() -> LockAll {
    LockAll(Table::new().with("all", true))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dispatch::lua;

    #[test]
    fn groups() {
        assert_eq!(lua(toggle()), "hl.dsp.group.toggle({})");
        assert_eq!(
            lua(toggle().window(WindowSelector::Class("foot".into()))),
            r#"hl.dsp.group.toggle({ window = "class:foot" })"#
        );
        assert_eq!(lua(next()), "hl.dsp.group.next({})");
        assert_eq!(lua(prev()), "hl.dsp.group.prev({})");
        assert_eq!(
            lua(active(NonZeroU32::new(2).unwrap())),
            "hl.dsp.group.active({ index = 2 })"
        );
        assert_eq!(
            lua(move_window().forward(false)),
            "hl.dsp.group.move_window({ forward = false })"
        );
    }

    #[test]
    fn locks() {
        assert_eq!(lua(lock()), "hl.dsp.group.lock({})");
        assert_eq!(
            lua(lock().action(Action::Enable).window(WindowSelector::Active)),
            r#"hl.dsp.group.lock({ action = "enable", window = "active" })"#
        );
        assert_eq!(
            lua(lock_all().action(Action::Disable)),
            r#"hl.dsp.group.lock({ all = true, action = "disable" })"#
        );
    }
}

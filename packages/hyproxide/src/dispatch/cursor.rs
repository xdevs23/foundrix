//! The `hl.dsp.cursor.*` dispatchers.

use super::table_dispatcher;
use super::{Dispatcher, WindowSelector};
use crate::lua::{Table, Value};

/// A corner of a window.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Corner {
    BottomLeft,
    BottomRight,
    TopRight,
    TopLeft,
}

/// The number Hyprland uses for a corner (`moveCursorToCorner` in
/// <https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/config/shared/actions/ConfigActions.cpp>,
/// checked 2026-11-08).
impl From<Corner> for Value {
    fn from(corner: Corner) -> Self {
        Value::Integer(match corner {
            Corner::BottomLeft => 0,
            Corner::BottomRight => 1,
            Corner::TopRight => 2,
            Corner::TopLeft => 3,
        })
    }
}

table_dispatcher! {
    /// Move the cursor to a corner of the focused window, or of another one.
    MoveToCorner = "hl.dsp.cursor.move_to_corner" { window: WindowSelector }
}

pub fn move_to_corner(corner: Corner) -> MoveToCorner {
    MoveToCorner(Table::new().with("corner", corner))
}

/// Move the cursor to a position in the layout.
#[must_use]
pub fn move_to(x: f64, y: f64) -> Dispatcher {
    let table = Table::new().with("x", x).with("y", y);
    Dispatcher::with_argument("hl.dsp.cursor.move", table)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dispatch::lua;

    #[test]
    fn cursor() {
        assert_eq!(
            lua(move_to_corner(Corner::TopLeft).window(WindowSelector::Active)),
            r#"hl.dsp.cursor.move_to_corner({ corner = 3, window = "active" })"#
        );
        assert_eq!(
            lua(move_to_corner(Corner::BottomLeft)),
            "hl.dsp.cursor.move_to_corner({ corner = 0 })"
        );
        assert_eq!(
            lua(move_to(256.0, 192.5)),
            "hl.dsp.cursor.move({ x = 256, y = 192.5 })"
        );
    }
}

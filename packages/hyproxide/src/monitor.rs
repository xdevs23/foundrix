//! How Hyprland identifies monitors.

use std::fmt::{self, Display, Formatter};

/// The id Hyprland gives a monitor. Only answers and events of Hyprland
/// create one, so an id always belongs to a monitor that existed when it was
/// read.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct MonitorId(i64);

impl MonitorId {
    pub(crate) fn new(id: i64) -> Self {
        Self(id)
    }

    #[must_use]
    pub fn get(self) -> i64 {
        self.0
    }
}

impl Display for MonitorId {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

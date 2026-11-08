//! How Hyprland identifies windows and describes how they cover a monitor.

use std::fmt::{self, Display, Formatter};

/// The id Hyprland gives a window for its whole life, unlike its address. It
/// is displayed as lowercase hex.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct StableId(pub u64);

impl Display for StableId {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{:x}", self.0)
    }
}

/// How a window covers its monitor, as Hyprland tracks it and as the window
/// itself was told.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FullscreenState {
    None,
    Maximized,
    Fullscreen,
    /// A state this library does not know, by its number.
    Unknown(u8),
}

impl FullscreenState {
    /// The number Hyprland uses for this state (`eFullscreenMode` in
    /// <https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/managers/fullscreen/FullscreenTypes.hpp>,
    /// checked 2026-11-08).
    #[must_use]
    pub fn number(self) -> u8 {
        match self {
            FullscreenState::None => 0,
            FullscreenState::Maximized => 1,
            FullscreenState::Fullscreen => 2,
            FullscreenState::Unknown(number) => number,
        }
    }
}

impl From<u8> for FullscreenState {
    fn from(number: u8) -> Self {
        [Self::None, Self::Maximized, Self::Fullscreen]
            .into_iter()
            .find(|state| state.number() == number)
            .unwrap_or(Self::Unknown(number))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stable_ids_are_shown_as_bare_hex() {
        assert_eq!(StableId(0x1800_0001).to_string(), "18000001");
    }

    #[test]
    fn fullscreen_states_are_numbers() {
        let states: Vec<_> = [0, 1, 2, 3].map(FullscreenState::from).into();
        assert_eq!(
            states,
            [
                FullscreenState::None,
                FullscreenState::Maximized,
                FullscreenState::Fullscreen,
                FullscreenState::Unknown(3),
            ]
        );
        assert!(states.iter().zip(0..).all(|(state, n)| state.number() == n));
    }
}

//! Keyboard modifiers of binds and shortcuts in Hyprland.

/// One modifier key.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Modifier {
    Shift,
    Caps,
    Ctrl,
    Alt,
    Mod2,
    Mod3,
    Super,
    Mod5,
}

impl Modifier {
    const ALL: [Modifier; 8] = [
        Modifier::Shift,
        Modifier::Caps,
        Modifier::Ctrl,
        Modifier::Alt,
        Modifier::Mod2,
        Modifier::Mod3,
        Modifier::Super,
        Modifier::Mod5,
    ];

    /// The bit of this modifier in the modifier mask of Hyprland
    /// (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/input/Keys.hpp>,
    /// checked 2026-11-08).
    fn bit(self) -> u32 {
        match self {
            Modifier::Shift => 1 << 0,
            Modifier::Caps => 1 << 1,
            Modifier::Ctrl => 1 << 2,
            Modifier::Alt => 1 << 3,
            Modifier::Mod2 => 1 << 4,
            Modifier::Mod3 => 1 << 5,
            Modifier::Super => 1 << 6,
            Modifier::Mod5 => 1 << 7,
        }
    }

    /// The name Hyprland reads for this modifier.
    pub(crate) fn name(self) -> &'static str {
        match self {
            Modifier::Shift => "SHIFT",
            Modifier::Caps => "CAPS",
            Modifier::Ctrl => "CTRL",
            Modifier::Alt => "ALT",
            Modifier::Mod2 => "MOD2",
            Modifier::Mod3 => "MOD3",
            Modifier::Super => "SUPER",
            Modifier::Mod5 => "MOD5",
        }
    }
}

/// A set of modifiers.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash)]
pub struct Modifiers(u32);

impl Modifiers {
    /// The set of a modifier mask of Hyprland.
    pub(crate) fn from_mask(mask: u32) -> Self {
        Self(mask)
    }

    #[must_use]
    pub fn contains(self, modifier: Modifier) -> bool {
        self.0 & modifier.bit() != 0
    }

    /// The modifiers of this set.
    pub fn iter(self) -> impl Iterator<Item = Modifier> {
        Modifier::ALL
            .into_iter()
            .filter(move |modifier| self.contains(*modifier))
    }
}

impl FromIterator<Modifier> for Modifiers {
    fn from_iter<I: IntoIterator<Item = Modifier>>(modifiers: I) -> Self {
        Self(
            modifiers
                .into_iter()
                .fold(0, |mask, modifier| mask | modifier.bit()),
        )
    }
}

impl From<Modifier> for Modifiers {
    fn from(modifier: Modifier) -> Self {
        Self(modifier.bit())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mask_bits() {
        let modifiers = Modifiers::from_mask(65);
        assert_eq!(
            modifiers.iter().collect::<Vec<_>>(),
            [Modifier::Shift, Modifier::Super]
        );
        assert!(modifiers.contains(Modifier::Super));
        assert!(!modifiers.contains(Modifier::Alt));
        assert_eq!(
            modifiers,
            [Modifier::Super, Modifier::Shift].into_iter().collect()
        );
    }
}

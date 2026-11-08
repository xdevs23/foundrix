//! How Hyprland identifies windows, layers and input devices.

use std::fmt::{self, Display, Formatter};
use std::num::{NonZeroU64, ParseIntError};

/// Where an object lives in the memory of Hyprland, which is how Hyprland
/// identifies windows, layers and input devices. It is displayed as
/// lowercase hex after `0x`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Address(NonZeroU64);

impl Address {
    #[must_use]
    pub fn new(address: NonZeroU64) -> Self {
        Self(address)
    }

    #[must_use]
    pub fn get(self) -> NonZeroU64 {
        self.0
    }

    /// Read an address written as hex digits. Zero, the address Hyprland
    /// writes for no object, reads as `None`.
    pub(crate) fn from_hex(hex: &str) -> Result<Option<Self>, ParseIntError> {
        u64::from_str_radix(hex, 16).map(|address| NonZeroU64::new(address).map(Self))
    }
}

impl Display for Address {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "0x{:x}", self.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex_addresses() {
        let read = Address::from_hex("573106b0db30").unwrap().unwrap();
        assert_eq!(read.get().get(), 0x5731_06b0_db30);
        assert_eq!(read.to_string(), "0x573106b0db30");
        assert_eq!(Address::from_hex("0").unwrap(), None);
        assert!(Address::from_hex("0x1").is_err());
    }
}

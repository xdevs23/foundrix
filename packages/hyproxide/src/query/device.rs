//! The `devices` and `cursorpos` answers.

use serde::Deserialize;

use super::wire;
use crate::address::Address;
use crate::geometry::Position;

/// The `devices` answer: the input devices Hyprland knows.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Devices {
    pub mice: Vec<Mouse>,
    pub keyboards: Vec<KeyboardDevice>,
    pub tablets: Vec<TabletDevice>,
    pub touch: Vec<NamedDevice>,
    pub switches: Vec<NamedDevice>,
}

/// A pointer device: a mouse or a touchpad.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Mouse {
    #[serde(deserialize_with = "wire::address")]
    pub address: Address,
    pub name: String,
    /// The pointer speed libinput starts with.
    pub default_speed: f64,
    /// `None` unless the configuration sets one.
    #[serde(deserialize_with = "wire::scroll_factor")]
    pub scroll_factor: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyboardDevice {
    #[serde(deserialize_with = "wire::address")]
    pub address: Address,
    pub name: String,
    /// The XKB rules, model, layouts, variants and options.
    pub rules: String,
    pub model: String,
    pub layout: String,
    pub variant: String,
    pub options: String,
    #[serde(rename = "active_layout_index")]
    pub active_layout_index: u32,
    /// The name of the active layout, such as `German`.
    #[serde(rename = "active_keymap")]
    pub active_keymap: String,
    pub caps_lock: bool,
    pub num_lock: bool,
    /// Whether this is the keyboard whose layout Hyprland reports as the
    /// main one.
    pub main: bool,
}

/// An entry of the tablets list, which has three kinds of devices.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(try_from = "TabletEntry")]
pub enum TabletDevice {
    Pad {
        address: Address,
        /// The tablet the pad belongs to.
        belongs_to: Option<NamedDevice>,
    },
    Tablet(NamedDevice),
    Tool {
        address: Address,
    },
    /// A kind of device this library does not know.
    Unknown {
        address: Address,
    },
}

/// A tablets entry as Hyprland writes it: the `type` field tells the kind,
/// and a tablet has none.
#[derive(Deserialize)]
struct TabletEntry {
    #[serde(deserialize_with = "wire::address")]
    address: Address,
    #[serde(rename = "type")]
    kind: Option<TabletKind>,
    name: Option<String>,
    #[serde(rename = "belongsTo")]
    belongs_to: Option<PadTablet>,
}

#[derive(Deserialize)]
enum TabletKind {
    #[serde(rename = "tabletPad")]
    Pad,
    #[serde(rename = "tabletTool")]
    Tool,
    #[serde(other)]
    Unknown,
}

/// The tablet a pad belongs to, where the address `0x0` means none.
#[derive(Deserialize)]
struct PadTablet {
    #[serde(deserialize_with = "wire::optional_address")]
    address: Option<Address>,
    name: String,
}

impl TryFrom<TabletEntry> for TabletDevice {
    type Error = &'static str;

    fn try_from(entry: TabletEntry) -> Result<Self, Self::Error> {
        let TabletEntry {
            address,
            kind,
            name,
            belongs_to,
        } = entry;
        Ok(match kind {
            None => TabletDevice::Tablet(NamedDevice {
                address,
                name: name.ok_or("missing field `name` of a tablet")?,
            }),
            Some(TabletKind::Pad) => {
                let PadTablet {
                    address: tablet,
                    name,
                } = belongs_to.ok_or("missing field `belongsTo` of a tablet pad")?;
                TabletDevice::Pad {
                    address,
                    belongs_to: tablet.map(|address| NamedDevice { address, name }),
                }
            }
            Some(TabletKind::Tool) => TabletDevice::Tool { address },
            Some(TabletKind::Unknown) => TabletDevice::Unknown { address },
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct NamedDevice {
    #[serde(deserialize_with = "wire::address")]
    pub address: Address,
    pub name: String,
}

/// The `cursorpos` answer: the cursor position in the layout.
#[derive(Deserialize)]
#[serde(transparent)]
pub(super) struct CursorPosition(
    #[serde(deserialize_with = "wire::position_object")] pub(super) Position,
);

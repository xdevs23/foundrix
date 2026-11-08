//! Readers for the way the JSON answers of Hyprland write values: absence as
//! a placeholder of the same type, booleans and numbers as text, and the
//! identities of the crate, which have no serde form of their own.

use std::fmt::Display;
use std::str::FromStr;

use serde::Deserialize;
use serde::de::{self, Deserializer};

use super::monitor::Mode;
use crate::address::Address;
use crate::geometry::{Position, Size};
use crate::keyboard::Modifiers;
use crate::monitor::MonitorId;
use crate::window::{FullscreenState, StableId};
use crate::workspace::{WorkspaceId, WorkspaceKind, WorkspaceRef};

/// A number where `-1` means none.
pub(super) fn minus_one_as_none<'de, D, T>(deserializer: D) -> Result<Option<T>, D::Error>
where
    D: Deserializer<'de>,
    T: TryFrom<i64, Error: Display>,
{
    match i64::deserialize(deserializer)? {
        -1 => Ok(None),
        number => T::try_from(number).map(Some).map_err(de::Error::custom),
    }
}

/// A list where `null` means an empty one.
pub(super) fn null_as_empty<'de, D, T>(deserializer: D) -> Result<Vec<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    Ok(Option::<Vec<T>>::deserialize(deserializer)?.unwrap_or_default())
}

/// A text where the empty text means none.
pub(super) fn empty_as_none<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<String>, D::Error> {
    let text = String::deserialize(deserializer)?;
    Ok(Some(text).filter(|text| !text.is_empty()))
}

/// A text where `unknown` means none.
pub(super) fn unknown_as_none<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<String>, D::Error> {
    let text = String::deserialize(deserializer)?;
    Ok(Some(text).filter(|text| text != "unknown"))
}

/// A monitor name where `?` means none.
pub(super) fn question_mark_as_none<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<String>, D::Error> {
    let name = String::deserialize(deserializer)?;
    Ok(Some(name).filter(|name| name != "?"))
}

/// A boolean written as the text `true` or `false`.
pub(super) fn quoted_bool<'de, D: Deserializer<'de>>(deserializer: D) -> Result<bool, D::Error> {
    quoted(deserializer)
}

/// A count written as text, where `-1` means none.
pub(super) fn quoted_minus_one_as_none<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<u64>, D::Error> {
    match quoted::<D, i64>(deserializer)? {
        -1 => Ok(None),
        count => u64::try_from(count).map(Some).map_err(de::Error::custom),
    }
}

fn quoted<'de, D: Deserializer<'de>, T: FromStr>(deserializer: D) -> Result<T, D::Error> {
    let text = String::deserialize(deserializer)?;
    text.parse()
        .map_err(|_| de::Error::custom(format!("{text:?} is not a {}", std::any::type_name::<T>())))
}

/// A scroll factor, where a negative one means none.
pub(super) fn scroll_factor<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<f64>, D::Error> {
    let factor = f64::deserialize(deserializer)?;
    Ok(Some(factor).filter(|factor| *factor >= 0.0))
}

/// An address written as hex after `0x`, where `0x0` means none.
struct PrefixedAddress(Option<Address>);

impl<'de> Deserialize<'de> for PrefixedAddress {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let text = String::deserialize(deserializer)?;
        let hex = text
            .strip_prefix("0x")
            .ok_or_else(|| de::Error::custom(format!("{text:?} does not start with 0x")))?;
        bare_address(hex).map(Self)
    }
}

impl PrefixedAddress {
    fn required<E: de::Error>(self) -> Result<Address, E> {
        self.0
            .ok_or_else(|| E::custom("0x0 is the address of no object"))
    }
}

fn bare_address<E: de::Error>(hex: &str) -> Result<Option<Address>, E> {
    Address::from_hex(hex).map_err(E::custom)
}

pub(super) fn address<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Address, D::Error> {
    PrefixedAddress::deserialize(deserializer)?.required()
}

pub(super) fn addresses<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Vec<Address>, D::Error> {
    Vec::<PrefixedAddress>::deserialize(deserializer)?
        .into_iter()
        .map(PrefixedAddress::required)
        .collect()
}

pub(super) fn optional_address<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<Address>, D::Error> {
    PrefixedAddress::deserialize(deserializer).map(|address| address.0)
}

/// An address written as hex alone, where `0` means none.
pub(super) fn optional_bare_address<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<Address>, D::Error> {
    bare_address(&String::deserialize(deserializer)?)
}

/// A stable id, written as hex alone.
pub(super) fn stable_id<'de, D: Deserializer<'de>>(deserializer: D) -> Result<StableId, D::Error> {
    let text = String::deserialize(deserializer)?;
    u64::from_str_radix(&text, 16)
        .map(StableId)
        .map_err(|_| de::Error::custom(format!("{text:?} is not a hex stable id")))
}

pub(super) fn fullscreen_state<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<FullscreenState, D::Error> {
    u8::deserialize(deserializer).map(FullscreenState::from)
}

pub(super) fn modifiers<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Modifiers, D::Error> {
    u32::deserialize(deserializer).map(Modifiers::from_mask)
}

/// A position written as `[x, y]`.
pub(super) fn position_pair<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Position, D::Error> {
    <[i32; 2]>::deserialize(deserializer).map(|[x, y]| Position { x, y })
}

/// A position written as `{"x": …, "y": …}`.
pub(super) fn position_object<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Position, D::Error> {
    #[derive(Deserialize)]
    struct Point {
        x: i32,
        y: i32,
    }
    Point::deserialize(deserializer).map(|Point { x, y }| Position { x, y })
}

/// A size written as `[width, height]`.
pub(super) fn size<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Size, D::Error> {
    <[i32; 2]>::deserialize(deserializer).map(|[width, height]| Size { width, height })
}

pub(super) fn monitor_id<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<MonitorId, D::Error> {
    i64::deserialize(deserializer).map(MonitorId::new)
}

/// A monitor id where `null` means none.
pub(super) fn null_as_no_monitor<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<MonitorId>, D::Error> {
    Option::<i64>::deserialize(deserializer).map(|id| id.map(MonitorId::new))
}

/// A monitor id where `-1` means none.
pub(super) fn minus_one_as_no_monitor<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<MonitorId>, D::Error> {
    minus_one_as_none::<D, i64>(deserializer).map(|id| id.map(MonitorId::new))
}

/// A monitor id written as text, where `none` means none.
pub(super) fn quoted_monitor_or_none<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<MonitorId>, D::Error> {
    let text = String::deserialize(deserializer)?;
    if text == "none" {
        return Ok(None);
    }
    text.parse()
        .map(|id| Some(MonitorId::new(id)))
        .map_err(|_| de::Error::custom(format!("{text:?} is neither none nor a monitor id")))
}

/// Modes written as `<width>x<height>@<refresh rate>Hz`.
pub(super) fn modes<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Vec<Mode>, D::Error> {
    Vec::<String>::deserialize(deserializer)?
        .iter()
        .map(|text| mode(text))
        .collect()
}

fn mode<E: de::Error>(text: &str) -> Result<Mode, E> {
    let malformed = || E::custom(format!("{text:?} is not a mode such as 1920x1080@60.00Hz"));
    let (size, refresh_rate) = text
        .strip_suffix("Hz")
        .and_then(|text| text.split_once('@'))
        .ok_or_else(malformed)?;
    let (width, height) = size.split_once('x').ok_or_else(malformed)?;
    Ok(Mode {
        width: width.parse().map_err(|_| malformed())?,
        height: height.parse().map_err(|_| malformed())?,
        refresh_rate_hz: refresh_rate.parse().map_err(|_| malformed())?,
    })
}

/// The workspace object embedded in answers. It also reads the workspace
/// fields of a `workspaces` entry, when flattened.
pub(super) fn workspace<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<WorkspaceRef, D::Error> {
    #[derive(Deserialize)]
    struct Workspace {
        id: Option<u32>,
        #[serde(rename = "type")]
        kind: Kind,
        address: String,
        name: String,
    }

    #[derive(Deserialize)]
    enum Kind {
        #[serde(rename = "normal")]
        Normal,
        #[serde(rename = "special")]
        Special,
        #[serde(rename = "")]
        None,
    }

    let Workspace {
        id,
        kind,
        address,
        name,
    } = Workspace::deserialize(deserializer)?;
    Ok(WorkspaceRef {
        id: id
            .map(WorkspaceId::try_from)
            .transpose()
            .map_err(de::Error::custom)?,
        kind: match kind {
            Kind::Normal => WorkspaceKind::Normal,
            Kind::Special => WorkspaceKind::Special,
            Kind::None => WorkspaceKind::None,
        },
        address,
        name,
    })
}

#[cfg(test)]
mod tests;

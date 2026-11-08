//! The `monitors` answer.

use serde::Deserialize;

use super::flags::{Flags, flag_set};
use super::wire;
use crate::address::Address;
use crate::monitor::MonitorId;
use crate::workspace::WorkspaceRef;

/// An entry of the `monitors` answer: one monitor, enabled or not.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Monitor {
    #[serde(deserialize_with = "wire::monitor_id")]
    pub id: MonitorId,
    pub name: String,
    pub description: String,
    pub make: String,
    pub model: String,
    pub serial: String,
    /// The mode in pixels.
    pub width: i32,
    pub height: i32,
    /// The size in millimeters.
    pub physical_width: i32,
    pub physical_height: i32,
    pub refresh_rate: f64,
    /// The position in the layout.
    pub x: i32,
    pub y: i32,
    #[serde(deserialize_with = "wire::workspace")]
    pub active_workspace: WorkspaceRef,
    #[serde(deserialize_with = "wire::workspace")]
    pub special_workspace: WorkspaceRef,
    /// The space that layers such as bars reserve.
    pub reserved: Edges,
    pub scale: f64,
    pub transform: Transform,
    #[serde(flatten)]
    pub flags: Flags<MonitorFlag>,
    /// The window shown alone on the monitor.
    #[serde(deserialize_with = "wire::optional_bare_address")]
    pub solitary: Option<Address>,
    #[serde(deserialize_with = "wire::null_as_empty")]
    pub solitary_blocked_by: Vec<SolitaryBlocker>,
    #[serde(deserialize_with = "wire::null_as_empty")]
    pub tearing_blocked_by: Vec<TearingBlocker>,
    /// The surface last scanned out directly.
    #[serde(deserialize_with = "wire::optional_bare_address")]
    pub direct_scanout_to: Option<Address>,
    #[serde(deserialize_with = "wire::null_as_empty")]
    pub direct_scanout_blocked_by: Vec<ScanoutBlocker>,
    pub current_format: PixelFormat,
    /// The monitor this one mirrors.
    #[serde(deserialize_with = "wire::quoted_monitor_or_none")]
    pub mirror_of: Option<MonitorId>,
    #[serde(deserialize_with = "wire::modes")]
    pub available_modes: Vec<Mode>,
    pub color_management_preset: ColorPreset,
    pub sdr_brightness: f64,
    pub sdr_saturation: f64,
    pub sdr_min_luminance: f64,
    pub sdr_max_luminance: f64,
    pub hardware_details: HardwareDetails,
}

flag_set! {
    /// The yes-or-no facts about a monitor.
    pub enum MonitorFlag {
        Focused = "focused",
        /// The monitor is powered on.
        DpmsStatus = "dpmsStatus",
        Vrr = "vrr",
        ActivelyTearing = "activelyTearing",
        Disabled = "disabled",
        HardwareCursorsInUse = "hardwareCursorsInUse",
    }
}

/// A mode a monitor can show.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Mode {
    pub width: u32,
    pub height: u32,
    pub refresh_rate_hz: f64,
}

/// Widths along the four edges of a monitor.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(from = "[i32; 4]")]
pub struct Edges {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

impl From<[i32; 4]> for Edges {
    fn from([left, top, right, bottom]: [i32; 4]) -> Self {
        Self {
            left,
            top,
            right,
            bottom,
        }
    }
}

/// How the picture is rotated and flipped.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(from = "u8")]
pub enum Transform {
    Normal,
    Rotated90,
    Rotated180,
    Rotated270,
    Flipped,
    Flipped90,
    Flipped180,
    Flipped270,
    /// A transform this library does not know, by its number.
    Unknown(u8),
}

impl From<u8> for Transform {
    /// The values of `wl_output.transform`
    /// (<https://gitlab.freedesktop.org/wayland/wayland/-/blob/main/protocol/wayland.xml>,
    /// checked 2026-11-08).
    fn from(number: u8) -> Self {
        match number {
            0 => Transform::Normal,
            1 => Transform::Rotated90,
            2 => Transform::Rotated180,
            3 => Transform::Rotated270,
            4 => Transform::Flipped,
            5 => Transform::Flipped90,
            6 => Transform::Flipped180,
            7 => Transform::Flipped270,
            other => Transform::Unknown(other),
        }
    }
}

/// Why a monitor does not show one window alone.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum SolitaryBlocker {
    Notification,
    Lock,
    Workspace,
    Windowed,
    Dnd,
    Special,
    Alpha,
    Offset,
    Candidate,
    Opaque,
    Transform,
    Overlays,
    Float,
    Workspaces,
    Surfaces,
    #[serde(rename = "CONFIGERROR")]
    ConfigError,
    #[serde(rename = "FADEOUT")]
    FadeOut,
    #[serde(other)]
    Unknown,
}

/// Why a monitor does not tear.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum TearingBlocker {
    NotTorn,
    User,
    Zoom,
    Support,
    Candidate,
    Window,
    HwCursor,
    #[serde(other)]
    Unknown,
}

/// Why a monitor does not scan a surface out directly.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ScanoutBlocker {
    User,
    Windowed,
    Content,
    Mirror,
    Record,
    #[serde(rename = "SW")]
    Software,
    Candidate,
    Surface,
    Transform,
    #[serde(rename = "DMA")]
    Buffer,
    Failed,
    #[serde(rename = "CM")]
    ColorManagement,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub enum PixelFormat {
    #[serde(rename = "XRGB2101010")]
    Xrgb2101010,
    #[serde(rename = "XBGR2101010")]
    Xbgr2101010,
    #[serde(rename = "XRGB8888")]
    Xrgb8888,
    #[serde(rename = "XBGR8888")]
    Xbgr8888,
    /// A format Hyprland has no name for.
    #[serde(other)]
    Invalid,
}

/// The color management preset of a monitor.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ColorPreset {
    Auto,
    Srgb,
    Wide,
    Edid,
    Hdr,
    HdrEdid,
    Dcip3,
    Dp3,
    Adobe,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct HardwareDetails {
    pub backend: Backend,
    #[serde(flatten)]
    pub flags: Flags<HardwareFlag>,
}

flag_set! {
    /// What the display reports to support.
    pub enum HardwareFlag {
        /// HDR metadata in the EDID.
        Hdr = "hdr",
        /// Chromaticity coordinates in the EDID.
        Chroma = "chroma",
        Bt2020 = "bt2020",
        VrrCapable = "vrrCapable",
    }
}

/// The backend that drives an output.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Backend {
    Drm,
    Headless,
    Wayland,
    #[serde(other)]
    Unknown,
}

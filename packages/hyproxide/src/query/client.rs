//! The `clients` and `activewindow` answers.

use serde::Deserialize;
use serde::de::{self, Deserializer};

use super::flags::{Flags, flag_set};
use super::wire;
use crate::address::Address;
use crate::geometry::{Position, Size};
use crate::monitor::MonitorId;
use crate::window::{FullscreenState, StableId};
use crate::workspace::WorkspaceRef;

/// An entry of the `clients` answer: one window.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Client {
    #[serde(deserialize_with = "wire::address")]
    pub address: Address,
    #[serde(flatten)]
    pub flags: Flags<ClientFlag>,
    /// The position in the layout.
    #[serde(deserialize_with = "wire::position_pair")]
    pub at: Position,
    #[serde(deserialize_with = "wire::size")]
    pub size: Size,
    /// [`WorkspaceAddress::None`](crate::workspace::WorkspaceAddress::None)
    /// for a window without a workspace.
    #[serde(deserialize_with = "wire::workspace")]
    pub workspace: WorkspaceRef,
    #[serde(deserialize_with = "wire::minus_one_as_no_monitor")]
    pub monitor: Option<MonitorId>,
    pub class: String,
    pub title: String,
    pub initial_class: String,
    pub initial_title: String,
    pub pid: i32,
    /// The state Hyprland tracks for the window.
    #[serde(deserialize_with = "wire::fullscreen_state")]
    pub fullscreen: FullscreenState,
    /// The state the window was told.
    #[serde(deserialize_with = "wire::fullscreen_state")]
    pub fullscreen_client: FullscreenState,
    pub fullscreen_handler: FullscreenHandler,
    /// The windows of its group, itself included; empty outside a group.
    #[serde(deserialize_with = "wire::addresses")]
    pub grouped: Vec<Address>,
    pub tags: Vec<String>,
    /// The window this one swallowed.
    #[serde(deserialize_with = "wire::optional_address")]
    pub swallowing: Option<Address>,
    /// How many windows got focus after this one, 0 for the focused one.
    #[serde(
        rename = "focusHistoryID",
        deserialize_with = "wire::minus_one_as_none"
    )]
    pub focus_history_id: Option<u32>,
    pub xdg_tag: String,
    pub xdg_description: String,
    pub content_type: ContentType,
    #[serde(deserialize_with = "wire::stable_id")]
    pub stable_id: StableId,
}

flag_set! {
    /// The yes-or-no facts about a window.
    pub enum ClientFlag {
        Mapped = "mapped",
        Hidden = "hidden",
        Visible = "visible",
        AcceptsInput = "acceptsInput",
        Floating = "floating",
        Xwayland = "xwayland",
        /// Shown on every workspace.
        Pinned = "pinned",
        /// Pinned again when it leaves fullscreen.
        PinFullscreened = "pinFullscreened",
        AllowedOverFullscreen = "allowedOverFullscreen",
        InhibitingIdle = "inhibitingIdle",
        /// The window asked to tear.
        TearingHint = "tearingHint",
    }
}

/// What makes a window fullscreen: Hyprland itself or the scrolling layout.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FullscreenHandler {
    Default,
    Scrolling,
    #[serde(other)]
    Unknown,
}

/// The kind of content a window reports to show.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ContentType {
    None,
    Photo,
    Video,
    Game,
    #[serde(other)]
    Unknown,
}

/// The `activewindow` answer: the focused window, or `{}` without one.
pub(super) struct ActiveWindow(pub(super) Option<Client>);

/// Reads `{}` as no window and any other object as a [`Client`], so a field
/// that does not read fails with its own cause.
impl<'de> Deserialize<'de> for ActiveWindow {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let object = serde_json::Map::deserialize(deserializer)?;
        if object.is_empty() {
            return Ok(Self(None));
        }
        Client::deserialize(serde_json::Value::Object(object))
            .map(|client| Self(Some(client)))
            .map_err(de::Error::custom)
    }
}

//! The state of Hyprland, read with the JSON forms of the requests of
//! hyprctl.
//!
//! Each function sends one request and reads its answer into typed values
//! with every field Hyprland 0.57 sends. Where Hyprland writes absence as a
//! placeholder, such as `0x0`, `-1` or `?`, the field is an `Option`.
//!
//! Every function fails with an [`Error`] when Hyprland is out of reach, with
//! [`Error::Refused`] when the answer is not JSON, such as `unsafe state` or
//! `no such option`, and with [`Error::Answer`] when the JSON does not read as
//! the type.

mod client;
mod config;
mod device;
mod flags;
mod layer;
mod monitor;
mod system;
mod wire;
mod workspace;

use std::collections::BTreeMap;

use serde::de::DeserializeOwned;
use serde_json::error::Category;

pub use client::{Client, ClientFlag, ContentType, FullscreenHandler};
pub use config::{
    Animation, Animations, Bezier, Bind, BindFlag, BindKey, ConfigOption, OptionValue,
};
pub use device::{Devices, KeyboardDevice, Mouse, NamedDevice, TabletDevice};
pub use flags::{Flag, Flags};
pub use layer::{Layer, Levels, MonitorLayers};
pub use monitor::{
    Backend, ColorPreset, Edges, HardwareDetails, HardwareFlag, Mode, Monitor, MonitorFlag,
    PixelFormat, ScanoutBlocker, SolitaryBlocker, TearingBlocker, Transform,
};
pub use system::{BuildFlag, ConfigProvider, SessionBackend, Status, Version};
pub use workspace::{Gaps, Workspace, WorkspaceRule};

use crate::error::{Error, Result};
use crate::geometry::Position;
use crate::socket::{Format, Instance};
use crate::word::Word;

/// All monitors, disabled ones included.
///
/// # Errors
///
/// See the [module documentation](self).
pub async fn monitors(instance: &Instance) -> Result<Vec<Monitor>> {
    read(instance, "monitors all").await
}

/// The mapped windows.
///
/// # Errors
///
/// See the [module documentation](self).
pub async fn clients(instance: &Instance) -> Result<Vec<Client>> {
    read(instance, "clients").await
}

/// The focused window, if there is one.
///
/// # Errors
///
/// See the [module documentation](self).
pub async fn active_window(instance: &Instance) -> Result<Option<Client>> {
    read(instance, "activewindow")
        .await
        .map(|client::ActiveWindow(window)| window)
}

/// # Errors
///
/// See the [module documentation](self).
pub async fn workspaces(instance: &Instance) -> Result<Vec<Workspace>> {
    read(instance, "workspaces").await
}

/// The active workspace of the focused monitor.
///
/// # Errors
///
/// See the [module documentation](self).
pub async fn active_workspace(instance: &Instance) -> Result<Workspace> {
    read(instance, "activeworkspace").await
}

/// # Errors
///
/// See the [module documentation](self).
pub async fn workspace_rules(instance: &Instance) -> Result<Vec<WorkspaceRule>> {
    read(instance, "workspacerules").await
}

/// The mapped layer surfaces of each monitor, by monitor name.
///
/// # Errors
///
/// See the [module documentation](self).
pub async fn layers(instance: &Instance) -> Result<BTreeMap<String, MonitorLayers>> {
    read(instance, "layers").await
}

/// # Errors
///
/// See the [module documentation](self). Hyprland 0.57.1 writes the active
/// layout index of a keyboard without an active layout as the bare word
/// `none`, which is not JSON, so the request then fails as a whole with
/// [`Error::Refused`], whose answer is the text Hyprland returned.
pub async fn devices(instance: &Instance) -> Result<Devices> {
    read(instance, "devices").await
}

/// The position of the cursor in the layout.
///
/// # Errors
///
/// See the [module documentation](self).
pub async fn cursor_position(instance: &Instance) -> Result<Position> {
    read(instance, "cursorpos")
        .await
        .map(|device::CursorPosition(position)| position)
}

/// # Errors
///
/// See the [module documentation](self).
pub async fn binds(instance: &Instance) -> Result<Vec<Bind>> {
    read(instance, "binds").await
}

/// # Errors
///
/// See the [module documentation](self).
pub async fn animations(instance: &Instance) -> Result<Animations> {
    read(instance, "animations").await
}

/// The value of a configuration option, such as `general:border_size`.
///
/// # Errors
///
/// See the [module documentation](self).
pub async fn option(instance: &Instance, name: &Word) -> Result<ConfigOption> {
    read(instance, &format!("getoption {name}")).await
}

/// The errors of the most recent configuration load, [`eval`] or
/// [`dispatch`]: Hyprland empties the list before each of them
/// (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/ipc/s1/Commands.cpp>,
/// checked 2026-11-08).
///
/// [`eval`]: crate::dispatch::eval
/// [`dispatch`]: crate::dispatch::dispatch
///
/// # Errors
///
/// See the [module documentation](self).
pub async fn config_errors(instance: &Instance) -> Result<Vec<String>> {
    read::<config::ConfigErrors>(instance, "configerrors")
        .await
        .map(Vec::from)
}

/// The name of the active submap, `default` outside every submap.
///
/// # Errors
///
/// See the [module documentation](self).
pub async fn submap(instance: &Instance) -> Result<String> {
    read(instance, "submap").await
}

/// Whether the session is locked.
///
/// # Errors
///
/// See the [module documentation](self).
pub async fn locked(instance: &Instance) -> Result<bool> {
    read::<system::Locked>(instance, "locked")
        .await
        .map(|answer| answer.locked)
}

/// # Errors
///
/// See the [module documentation](self).
pub async fn version(instance: &Instance) -> Result<Version> {
    read(instance, "version").await
}

/// # Errors
///
/// See the [module documentation](self).
pub async fn status(instance: &Instance) -> Result<Status> {
    read(instance, "status").await
}

async fn read<T: DeserializeOwned>(instance: &Instance, request: &str) -> Result<T> {
    let answer = instance.exchange(Format::Json, request).await?;
    decode(request, answer)
}

/// Read an answer, or fail with the request and the answer as it came:
/// Hyprland returns text that is not JSON for a request that fails.
fn decode<T: DeserializeOwned>(request: &str, answer: String) -> Result<T> {
    serde_json::from_str(&answer).map_err(|source| match source.classify() {
        Category::Syntax | Category::Eof => Error::Refused {
            request: request.to_owned(),
            answer,
        },
        Category::Data | Category::Io => Error::Answer {
            request: request.to_owned(),
            answer,
            source,
        },
    })
}

#[cfg(test)]
mod tests;

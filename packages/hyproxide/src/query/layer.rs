//! The `layers` answer.

use serde::Deserialize;

use super::wire;
use crate::address::Address;

/// The mapped layer surfaces of one monitor.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct MonitorLayers {
    pub levels: Levels,
}

/// Layer surfaces by the layer of the wlr layer shell protocol they are on,
/// which Hyprland numbers from 0 at the bottom.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Levels {
    #[serde(rename = "0")]
    pub background: Vec<Layer>,
    #[serde(rename = "1")]
    pub bottom: Vec<Layer>,
    #[serde(rename = "2")]
    pub top: Vec<Layer>,
    #[serde(rename = "3")]
    pub overlay: Vec<Layer>,
}

/// One layer surface, such as a bar or a wallpaper.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Layer {
    #[serde(deserialize_with = "wire::address")]
    pub address: Address,
    pub x: f64,
    pub y: f64,
    #[serde(rename = "w")]
    pub width: f64,
    #[serde(rename = "h")]
    pub height: f64,
    /// From 0 to 1.
    pub alpha: f64,
    pub namespace: String,
    pub pid: i32,
}

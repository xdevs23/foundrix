//! The `version`, `status` and `locked` answers.

use serde::Deserialize;

use super::wire;

/// The `version` answer: how the running Hyprland was built.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Version {
    pub branch: String,
    pub commit: String,
    pub version: String,
    /// Whether the build had uncommitted changes.
    pub dirty: bool,
    #[serde(rename = "commit_message")]
    pub commit_message: String,
    #[serde(rename = "commit_date")]
    pub commit_date: String,
    pub tag: String,
    /// The number of commits in the history of the build, if the build
    /// knew it.
    #[serde(deserialize_with = "wire::quoted_minus_one_as_none")]
    pub commits: Option<u64>,
    /// Versions of the libraries Hyprland was built against.
    pub build_aquamarine: String,
    pub build_hyprlang: String,
    pub build_hyprutils: String,
    pub build_hyprcursor: String,
    pub build_hyprgraphics: String,
    /// Versions of the libraries found on the system, `unknown` when not
    /// found.
    pub system_aquamarine: String,
    pub system_hyprlang: String,
    pub system_hyprutils: String,
    pub system_hyprcursor: String,
    pub system_hyprgraphics: String,
    /// The hash plugins are checked against.
    pub abi_hash: String,
    pub flags: Vec<BuildFlag>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
pub enum BuildFlag {
    #[serde(rename = "debug")]
    Debug,
    #[serde(rename = "no xwayland")]
    NoXwayland,
    #[serde(rename = "nix")]
    Nix,
    #[serde(other)]
    Unknown,
}

/// The `status` answer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub config_provider: ConfigProvider,
    /// The backend of the session, apart from headless outputs.
    pub backend: SessionBackend,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ConfigProvider {
    Lua,
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SessionBackend {
    Drm,
    Wayland,
    #[serde(other)]
    Unknown,
}

/// The `locked` answer.
#[derive(Deserialize)]
pub(super) struct Locked {
    pub(super) locked: bool,
}

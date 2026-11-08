//! Answers about the configuration: `binds`, `animations`, `getoption` and
//! `configerrors`.

use serde::Deserialize;

use super::flags::{Flags, flag_set};
use super::wire;
use crate::keyboard::Modifiers;

/// An entry of the `binds` answer.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(try_from = "BindEntry")]
pub struct Bind {
    pub flags: Flags<BindFlag>,
    pub modifiers: Modifiers,
    /// The submap the bind belongs to, `None` for binds outside submaps.
    pub submap: Option<String>,
    /// Whether the bind works in every submap.
    pub submap_universal: bool,
    pub key: BindKey,
    pub description: Option<String>,
    /// How the Lua of Hyprland shows the bound action, such as
    /// `HL.Dispatcher(close)` or `function: 0x…`.
    pub dispatcher: String,
    pub arg: String,
}

/// The key that triggers a bind.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BindKey {
    /// A key by its name, such as `Return` or `mouse:272`.
    Name(String),
    /// A key by its key code.
    Code(u32),
    /// Every key.
    CatchAll,
}

flag_set! {
    /// How a bind behaves.
    pub enum BindFlag {
        /// Works while the session is locked.
        Locked = "locked",
        Mouse = "mouse",
        /// Fires when the key is released.
        Release = "release",
        Repeat = "repeat",
        LongPress = "longPress",
        /// Passes the key on to the focused window.
        NonConsuming = "non_consuming",
        AutoConsuming = "auto_consuming",
        HasDescription = "has_description",
        AllowInputCapture = "allow_input_capture",
    }
}

/// A `binds` entry as Hyprland writes it: the key as a name, a code or the
/// `catch_all` flag, where an empty name and the code 0 mean none.
#[derive(Deserialize)]
struct BindEntry {
    #[serde(flatten)]
    flags: Flags<BindFlag>,
    #[serde(rename = "modmask", deserialize_with = "wire::modifiers")]
    modifiers: Modifiers,
    #[serde(deserialize_with = "wire::empty_as_none")]
    submap: Option<String>,
    #[serde(deserialize_with = "wire::quoted_bool")]
    submap_universal: bool,
    key: String,
    keycode: u32,
    catch_all: bool,
    #[serde(deserialize_with = "wire::empty_as_none")]
    description: Option<String>,
    dispatcher: String,
    arg: String,
}

impl TryFrom<BindEntry> for Bind {
    type Error = String;

    fn try_from(entry: BindEntry) -> Result<Self, Self::Error> {
        let BindEntry {
            flags,
            modifiers,
            submap,
            submap_universal,
            key,
            keycode,
            catch_all,
            description,
            dispatcher,
            arg,
        } = entry;
        let key = match (key.is_empty(), keycode, catch_all) {
            (false, 0, false) => BindKey::Name(key),
            (true, 0, true) => BindKey::CatchAll,
            (true, code, false) if code != 0 => BindKey::Code(code),
            _ => {
                return Err(format!(
                    "the key {key:?}, key code {keycode} and catch_all {catch_all} of a bind \
                     do not describe one key"
                ));
            }
        };
        Ok(Self {
            flags,
            modifiers,
            submap,
            submap_universal,
            key,
            description,
            dispatcher,
            arg,
        })
    }
}

/// The `animations` answer, which Hyprland writes as a list of the two lists.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(from = "(Vec<Animation>, Vec<Bezier>)")]
pub struct Animations {
    pub animations: Vec<Animation>,
    pub beziers: Vec<Bezier>,
}

impl From<(Vec<Animation>, Vec<Bezier>)> for Animations {
    fn from((animations, beziers): (Vec<Animation>, Vec<Bezier>)) -> Self {
        Self {
            animations,
            beziers,
        }
    }
}

/// A leaf of the animation tree.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Animation {
    pub name: String,
    /// Whether the configuration sets this leaf, instead of inheriting it.
    pub overridden: bool,
    pub bezier: String,
    pub enabled: bool,
    pub speed: f64,
    pub style: String,
}

/// A bezier curve by its two inner control points.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Bezier {
    pub name: String,
    #[serde(rename = "X0")]
    pub x0: f64,
    #[serde(rename = "Y0")]
    pub y0: f64,
    #[serde(rename = "X1")]
    pub x1: f64,
    #[serde(rename = "Y1")]
    pub y1: f64,
}

/// The `getoption` answer: the value of one configuration option.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct ConfigOption {
    pub option: String,
    #[serde(flatten)]
    pub value: OptionValue,
    /// Whether the configuration sets the option.
    pub set: bool,
}

/// The value of an option, by its type. Hyprland writes the complex types as
/// text.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OptionValue {
    Int(i64),
    Bool(bool),
    Float(f64),
    Vec2([f64; 2]),
    Str(String),
    Custom(String),
    /// Gaps along the four edges, such as `2 2 2 2`.
    Css(String),
    Gradient(String),
    FontWeight(String),
}

/// The `configerrors` answer, which lists one empty line when there are no
/// errors.
#[derive(Deserialize)]
#[serde(transparent)]
pub(super) struct ConfigErrors(Vec<String>);

impl From<ConfigErrors> for Vec<String> {
    fn from(ConfigErrors(lines): ConfigErrors) -> Self {
        lines.into_iter().filter(|line| !line.is_empty()).collect()
    }
}

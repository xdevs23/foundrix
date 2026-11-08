//! A client for the command and event sockets of Hyprland 0.57 and later,
//! whose configuration is Lua.
//!
//! * [`Instance`] finds a running Hyprland and sends requests to it.
//! * [`event`] reads the events of Hyprland into typed values.
//! * [`query`] reads the state of Hyprland into typed answers.
//! * [`dispatch`] runs `hl.dsp.*` dispatchers, Lua code and the plain
//!   commands of hyprctl.
//! * [`lua`] writes the Lua text of those requests.
//! * [`address`], [`window`], [`workspace`], [`monitor`], [`keyboard`],
//!   [`geometry`] and [`Word`] are the identities and values that answers,
//!   events and requests share. Of the other modules, they use only the
//!   errors.

#![forbid(unsafe_code)]

pub mod address;
pub mod dispatch;
mod error;
pub mod event;
pub mod geometry;
mod hex;
pub mod keyboard;
pub mod lua;
pub mod monitor;
pub mod query;
mod socket;
pub mod window;
mod word;
pub mod workspace;

pub use error::{Error, Result};
pub use socket::Instance;
pub use word::{NotAWord, Word};

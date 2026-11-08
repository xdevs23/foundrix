//! Fixtures for tests of programs that talk to Hyprland: temporary
//! directories, a headless Hyprland 0.57 that a test starts for itself, and
//! the reading of its events.
//!
//! A test that starts Hyprland takes over the display of the machine, so
//! such tests run one at a time, and only in a NixOS VM check.

#![forbid(unsafe_code)]

mod events;
mod hyprland;
mod notify;
mod temp_directory;

pub use events::read_until;
pub use hyprland::{HyprlandEnvironment, with_hyprland, with_hyprland_environment};
pub use notify::wait_for_ready;
pub use temp_directory::TempDirectory;

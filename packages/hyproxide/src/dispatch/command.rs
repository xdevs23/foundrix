//! The plain commands of hyprctl: requests other than `dispatch` and `eval`
//! that change the state of Hyprland. Hyprland splits their arguments at
//! spaces, so every argument is a [`Word`] except a message, the last
//! argument of a command.

use std::fmt::{self, Display, Formatter};
use std::time::Duration;

use crate::error::Result;
use crate::socket::Instance;
use crate::word::Word;

/// One plain command.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    /// Read the configuration again. With `full_reset`, start from a new
    /// configuration manager.
    Reload {
        full_reset: bool,
    },
    /// Let the next click kill the window under the cursor.
    Kill,
    Notify(Notification),
    /// Close the given number of notifications, or all of them.
    DismissNotifications(Option<u32>),
    /// Add an output to a backend, named by Hyprland unless a name is given.
    CreateOutput {
        backend: OutputBackend,
        name: Option<Word>,
    },
    /// Remove an output that `CreateOutput` added.
    RemoveOutput(Word),
    SetCursor {
        theme: Word,
        size: u32,
    },
    SwitchKeyboardLayout {
        keyboard: KeyboardTarget,
        layout: LayoutChoice,
    },
    /// Show an error bar at the top of the screen.
    ShowError {
        color: Color,
        message: String,
    },
    HideError,
    ReloadShaders,
}

/// Run a plain command.
///
/// # Errors
///
/// Fails when Hyprland is out of reach or returns anything but `ok`.
pub async fn run(instance: &Instance, command: &Command) -> Result<()> {
    super::send(instance, &command.to_string()).await
}

/// The request text of a command.
impl Display for Command {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Command::Reload { full_reset: false } => f.write_str("reload"),
            Command::Reload { full_reset: true } => f.write_str("reload full-reset"),
            Command::Kill => f.write_str("kill"),
            Command::Notify(notification) => {
                let Notification {
                    icon,
                    duration,
                    color,
                    font_size,
                    message,
                } = notification;
                write!(
                    f,
                    "notify {} {} {color} ",
                    icon.number(),
                    duration.as_millis()
                )?;
                if let Some(size) = font_size {
                    write!(f, "fontsize:{size} ")?;
                }
                f.write_str(message)
            }
            Command::DismissNotifications(None) => f.write_str("dismissnotify"),
            Command::DismissNotifications(Some(count)) => write!(f, "dismissnotify {count}"),
            Command::CreateOutput { backend, name } => {
                write!(f, "output create {}", backend.name())?;
                match name {
                    Some(name) => write!(f, " {name}"),
                    None => Ok(()),
                }
            }
            Command::RemoveOutput(name) => write!(f, "output remove {name}"),
            Command::SetCursor { theme, size } => write!(f, "setcursor {theme} {size}"),
            Command::SwitchKeyboardLayout { keyboard, layout } => {
                write!(f, "switchxkblayout {keyboard} {layout}")
            }
            Command::ShowError { color, message } => write!(f, "seterror {color} {message}"),
            Command::HideError => f.write_str("seterror disable"),
            Command::ReloadShaders => f.write_str("reloadshaders"),
        }
    }
}

/// A notification in the corner of the screen.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notification {
    pub icon: Icon,
    /// How long the notification shows, counted in milliseconds.
    pub duration: Duration,
    pub color: Color,
    /// Hyprland uses 13 without one.
    pub font_size: Option<u32>,
    pub message: String,
}

/// The icon of a notification.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Icon {
    Warning,
    Info,
    Hint,
    Error,
    Confused,
    Ok,
    None,
}

impl Icon {
    /// The number Hyprland uses for the icon (`eIcons` in
    /// <https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/SharedDefs.hpp>,
    /// checked 2026-11-08).
    fn number(self) -> u8 {
        match self {
            Icon::Warning => 0,
            Icon::Info => 1,
            Icon::Hint => 2,
            Icon::Error => 3,
            Icon::Confused => 4,
            Icon::Ok => 5,
            Icon::None => 6,
        }
    }
}

/// A color with transparency, written as `#rrggbbaa`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Color {
    pub red: u8,
    pub green: u8,
    pub blue: u8,
    pub alpha: u8,
}

impl Display for Color {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        let Color {
            red,
            green,
            blue,
            alpha,
        } = self;
        write!(f, "#{red:02x}{green:02x}{blue:02x}{alpha:02x}")
    }
}

/// The backend that gets a new output.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OutputBackend {
    Headless,
    Wayland,
    /// The first backend that can add one.
    Auto,
}

impl OutputBackend {
    fn name(self) -> &'static str {
        match self {
            OutputBackend::Headless => "headless",
            OutputBackend::Wayland => "wayland",
            OutputBackend::Auto => "auto",
        }
    }
}

/// The keyboards whose layout `SwitchKeyboardLayout` switches.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeyboardTarget {
    /// The keyboard Hyprland marks as main.
    Main,
    All,
    /// A keyboard by the name listed in the `devices` answer.
    Named(Word),
}

impl Display for KeyboardTarget {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            KeyboardTarget::Main => f.write_str("main"),
            KeyboardTarget::All => f.write_str("all"),
            KeyboardTarget::Named(name) => write!(f, "{name}"),
        }
    }
}

/// The layout a keyboard switches to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LayoutChoice {
    Next,
    Previous,
    /// The layout at a position, from 0, in the layout list of the keyboard.
    Index(u32),
}

impl Display for LayoutChoice {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            LayoutChoice::Next => f.write_str("next"),
            LayoutChoice::Previous => f.write_str("prev"),
            LayoutChoice::Index(index) => write!(f, "{index}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn word(text: &str) -> Word {
        Word::try_from(text).unwrap()
    }

    const RED: Color = Color {
        red: 0xff,
        green: 0x10,
        blue: 0,
        alpha: 0xcc,
    };

    #[test]
    fn notifications() {
        let notification = Notification {
            icon: Icon::Ok,
            duration: Duration::from_secs(2),
            color: RED,
            font_size: None,
            message: "Switched to speakers".into(),
        };
        assert_eq!(
            Command::Notify(notification.clone()).to_string(),
            "notify 5 2000 #ff1000cc Switched to speakers"
        );
        let larger = Notification {
            font_size: Some(20),
            icon: Icon::None,
            ..notification
        };
        assert_eq!(
            Command::Notify(larger).to_string(),
            "notify 6 2000 #ff1000cc fontsize:20 Switched to speakers"
        );
        assert_eq!(
            Command::DismissNotifications(None).to_string(),
            "dismissnotify"
        );
        assert_eq!(
            Command::DismissNotifications(Some(2)).to_string(),
            "dismissnotify 2"
        );
    }

    #[test]
    fn outputs() {
        let headless = Command::CreateOutput {
            backend: OutputBackend::Headless,
            name: Some(word("HEADLESS-2")),
        };
        assert_eq!(headless.to_string(), "output create headless HEADLESS-2");
        let unnamed = Command::CreateOutput {
            backend: OutputBackend::Auto,
            name: None,
        };
        assert_eq!(unnamed.to_string(), "output create auto");
        assert_eq!(
            Command::RemoveOutput(word("HEADLESS-2")).to_string(),
            "output remove HEADLESS-2"
        );
    }

    #[test]
    fn configuration_and_session() {
        assert_eq!(Command::Reload { full_reset: false }.to_string(), "reload");
        assert_eq!(
            Command::Reload { full_reset: true }.to_string(),
            "reload full-reset"
        );
        assert_eq!(Command::Kill.to_string(), "kill");
        assert_eq!(Command::ReloadShaders.to_string(), "reloadshaders");
        let cursor = Command::SetCursor {
            theme: word("Adwaita"),
            size: 24,
        };
        assert_eq!(cursor.to_string(), "setcursor Adwaita 24");
        let error = Command::ShowError {
            color: RED,
            message: "config broken".into(),
        };
        assert_eq!(error.to_string(), "seterror #ff1000cc config broken");
        assert_eq!(Command::HideError.to_string(), "seterror disable");
    }

    #[test]
    fn keyboard_layouts() {
        let switch =
            |keyboard, layout| Command::SwitchKeyboardLayout { keyboard, layout }.to_string();
        assert_eq!(
            switch(KeyboardTarget::Main, LayoutChoice::Next),
            "switchxkblayout main next"
        );
        assert_eq!(
            switch(KeyboardTarget::All, LayoutChoice::Previous),
            "switchxkblayout all prev"
        );
        assert_eq!(
            switch(
                KeyboardTarget::Named(word("at-translated-set-2-keyboard")),
                LayoutChoice::Index(1)
            ),
            "switchxkblayout at-translated-set-2-keyboard 1"
        );
    }
}

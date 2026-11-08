//! Commands for Hyprland: the `hl.dsp.*` dispatchers, Lua code, and the plain
//! commands of hyprctl.
//!
//! Each `hl.dsp` group has a module here with one builder per dispatcher, and
//! the dispatchers at the top of `hl.dsp` are in this module itself. A builder
//! takes the arguments a dispatcher requires, has a method for each optional
//! one, and turns into a [`Dispatcher`] for [`dispatch`]. [`rule`] builds the
//! rule functions of the configuration the same way, and sends them through
//! [`eval`]. Hyprland returns
//! `ok` for a dispatcher, Lua code and a command that succeed, and any other
//! answer is an [`Error::Refused`] that contains it.

pub mod command;
pub mod cursor;
pub mod group;
pub mod rule;
mod selector;
mod toplevel;
pub mod window;
pub mod workspace;

pub use selector::{
    Action, Direction, MonitorScope, MonitorSelector, WindowSelector, WorkspaceSelector,
};
pub use toplevel::{
    Dpms, Focus, KeyState, SendKeyState, SendShortcut, dpms, event, exec_cmd, exec_raw, exit,
    force_idle, force_renderer_reload, global, layout, no_op, pass, release_input_capture,
    reload_config, send_key_state, send_shortcut, submap,
};

use crate::error::{Error, Result};
use crate::lua::{Call, Value};
use crate::socket::{Format, Instance};

/// One dispatcher: the Lua expression that Hyprland hands to `hl.dispatch`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Dispatcher {
    lua: String,
}

impl Dispatcher {
    /// A dispatcher written in Lua: an `hl.dsp.*` call, or a function for
    /// `hl.dispatch` to run.
    pub fn lua(expression: impl Into<String>) -> Self {
        Self {
            lua: expression.into(),
        }
    }

    fn call(function: &'static str, arguments: Vec<Value>) -> Self {
        Self::lua(Call::new(function, arguments).to_string())
    }

    /// The call of a dispatcher function with one argument.
    fn with_argument(function: &'static str, argument: impl Into<Value>) -> Self {
        Self::call(function, vec![argument.into()])
    }

    /// The Lua expression of this dispatcher.
    #[must_use]
    pub fn as_lua(&self) -> &str {
        &self.lua
    }
}

/// Run a dispatcher.
///
/// Hyprland empties the list returned by
/// [`query::config_errors`](crate::query::config_errors) before it runs the
/// dispatcher, and adds the errors of the dispatcher to it.
///
/// # Errors
///
/// Fails when Hyprland is out of reach or returns anything but `ok`: an
/// error, warning or note of the dispatcher.
pub async fn dispatch(instance: &Instance, dispatcher: impl Into<Dispatcher>) -> Result<()> {
    send(instance, &format!("dispatch {}", dispatcher.into().lua)).await
}

/// Run Lua code in the configuration state of Hyprland, such as an
/// `hl.workspace_rule{...}` call.
///
/// Hyprland empties the list returned by
/// [`query::config_errors`](crate::query::config_errors) before it runs the
/// code, and adds the errors of the code to it.
///
/// # Errors
///
/// Fails when Hyprland is out of reach or returns anything but `ok`: an
/// error, warning or note of the code.
pub async fn eval(instance: &Instance, code: &str) -> Result<()> {
    send(instance, &format!("eval {code}")).await
}

/// Send a request whose only good answer is `ok`.
async fn send(instance: &Instance, request: &str) -> Result<()> {
    let answer = instance.exchange(Format::Text, request).await?;
    if answer == "ok" {
        Ok(())
    } else {
        Err(Error::Refused {
            request: request.to_owned(),
            answer,
        })
    }
}

/// Define the builder of a dispatcher whose argument is a table: a type that
/// contains the table, one method per optional field named like the field,
/// and the conversion into a [`Dispatcher`]. The function that creates the
/// builder sets the required fields.
macro_rules! table_dispatcher {
    (
        $(#[$meta:meta])*
        $name:ident = $function:literal {
            $($(#[$field_meta:meta])* $field:ident: $type:ty),* $(,)?
        }
    ) => {
        $(#[$meta])*
        #[derive(Debug, Clone, PartialEq)]
        #[must_use]
        pub struct $name($crate::lua::Table);

        impl $name {
            $(
                $(#[$field_meta])*
                pub fn $field(self, $field: impl Into<$type>) -> Self {
                    let value: $type = $field.into();
                    Self(self.0.with(stringify!($field), value))
                }
            )*
        }

        impl From<$name> for $crate::dispatch::Dispatcher {
            fn from(dispatcher: $name) -> Self {
                Self::with_argument($function, dispatcher.0)
            }
        }
    };
}
pub(crate) use table_dispatcher;

#[cfg(test)]
fn lua(dispatcher: impl Into<Dispatcher>) -> String {
    dispatcher.into().lua
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lua_dispatchers_are_sent_as_written() {
        let function = "function() hl.dispatch(hl.dsp.exit()) end";
        assert_eq!(lua(Dispatcher::lua(function)), function);
        assert_eq!(Dispatcher::lua(function).as_lua(), function);
    }
}

//! The command socket of a Hyprland instance, and how one request travels
//! over it.
//!
//! Hyprland reads a request until the client stops sending, writes its answer
//! and closes the connection, so a request goes out in one write and its
//! answer is everything read until the end of the stream.

use std::env;
use std::ffi::OsString;
use std::io;
use std::panic;
use std::path::{Path, PathBuf};

use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
use tokio::net::UnixStream;

use crate::error::{Error, Result};

/// The command socket in the directory of an instance
/// (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/ipc/s1/Unix.cpp>,
/// checked 2026-11-08).
const COMMAND_SOCKET: &str = ".socket.sock";

/// The variables a Hyprland session sets for the programs it starts.
const RUNTIME_DIRECTORY: &str = "XDG_RUNTIME_DIR";
const SIGNATURE: &str = "HYPRLAND_INSTANCE_SIGNATURE";

/// A running Hyprland, known by the directory Hyprland creates for it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Instance {
    directory: PathBuf,
}

impl Instance {
    /// The Hyprland of the session this program runs in, in
    /// `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE`, where Hyprland
    /// creates it and hyprctl looks for it.
    ///
    /// # Errors
    ///
    /// [`Error::NoInstance`] when either variable is unset or empty. Hyprland
    /// does not start without `XDG_RUNTIME_DIR`, so every program it starts
    /// has both.
    pub fn from_environment() -> Result<Self> {
        Self::from_variables(env::var_os(RUNTIME_DIRECTORY), env::var_os(SIGNATURE))
    }

    fn from_variables(
        runtime_directory: Option<OsString>,
        signature: Option<OsString>,
    ) -> Result<Self> {
        let set = |value: Option<OsString>, variable| {
            value
                .filter(|value| !value.is_empty())
                .ok_or(Error::NoInstance { variable })
        };
        let runtime_directory = PathBuf::from(set(runtime_directory, RUNTIME_DIRECTORY)?);
        let signature = set(signature, SIGNATURE)?;
        Ok(Self::at(runtime_directory.join("hypr").join(signature)))
    }

    /// The instance whose directory is `directory`, such as one a test
    /// started.
    pub fn at(directory: impl Into<PathBuf>) -> Self {
        Self {
            directory: directory.into(),
        }
    }

    /// Send one request and return the answer.
    pub(crate) async fn exchange(&self, format: Format, request: &str) -> Result<String> {
        let mut stream = connect(&self.directory.join(COMMAND_SOCKET)).await?;
        let framed = format!("{}/{request}", format.flag());
        let mut answer = Vec::new();
        let sent = async {
            stream.write_all(framed.as_bytes()).await?;
            stream.read_to_end(&mut answer).await
        };
        let _answer_length: usize = sent.await.map_err(|source| Error::Exchange {
            request: request.to_owned(),
            source,
        })?;
        String::from_utf8(answer).map_err(|source| Error::NotUtf8 {
            request: request.to_owned(),
            source,
        })
    }
}

/// The form of the answer Hyprland returns for a request.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Format {
    Text,
    Json,
}

impl Format {
    /// The flag hyprctl writes for this form before the slash of a request.
    fn flag(self) -> &'static str {
        match self {
            Format::Text => "",
            Format::Json => "j",
        }
    }
}

/// Connect to the socket at `path`. A connect that does not wait fails with
/// `EAGAIN` while the queue of the socket is full, and then a blocking connect
/// waits in the kernel until Hyprland accepts a queued connection or closes the
/// socket.
async fn connect(path: &Path) -> Result<UnixStream> {
    let connected = match UnixStream::connect(path).await {
        Err(full) if full.kind() == io::ErrorKind::WouldBlock => wait_for_room(path).await,
        connected => connected,
    };
    connected.map_err(|source| Error::Connect {
        path: path.to_owned(),
        source,
    })
}

/// Connect on a thread of the blocking pool, so the runtime goes on while the
/// kernel waits.
async fn wait_for_room(path: &Path) -> io::Result<UnixStream> {
    let path = path.to_owned();
    let waited =
        tokio::task::spawn_blocking(move || std::os::unix::net::UnixStream::connect(path)).await;
    // The task fails only by panicking: the runtime cancels a blocking task
    // only while it shuts down, and then nothing polls this future anymore.
    let stream = waited.unwrap_or_else(|failed| panic::resume_unwind(failed.into_panic()))?;
    stream.set_nonblocking(true)?;
    UnixStream::from_std(stream)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn instance(runtime_directory: Option<&str>, signature: Option<&str>) -> Result<Instance> {
        Instance::from_variables(runtime_directory.map(Into::into), signature.map(Into::into))
    }

    #[test]
    fn instance_directory_is_under_the_runtime_directory() {
        let found = instance(Some("/tmp/runtime"), Some("signature")).unwrap();
        assert_eq!(found, Instance::at("/tmp/runtime/hypr/signature"));
    }

    #[test]
    fn instance_needs_both_variables() {
        for (runtime_directory, signature, missing) in [
            (Some("/tmp/runtime"), None, "HYPRLAND_INSTANCE_SIGNATURE"),
            (
                Some("/tmp/runtime"),
                Some(""),
                "HYPRLAND_INSTANCE_SIGNATURE",
            ),
            (None, Some("signature"), "XDG_RUNTIME_DIR"),
            (Some(""), Some("signature"), "XDG_RUNTIME_DIR"),
        ] {
            let result = instance(runtime_directory, signature);
            assert!(
                matches!(result, Err(Error::NoInstance { variable }) if variable == missing),
                "{result:?}"
            );
        }
    }
}

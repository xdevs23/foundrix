//! The connection to the event socket, read line by line.

use std::path::PathBuf;

use tokio::io::{AsyncBufReadExt as _, BufReader};
use tokio::net::UnixStream;

use super::{Event, line};
use crate::error::{Error, Result};
use crate::socket::Instance;

/// Connect to the event socket of `instance`. The events arrive from the
/// moment Hyprland accepts the connection, which it does after this returns,
/// as the [module](super) tells.
///
/// # Errors
///
/// [`Error::Connect`] when the socket is out of reach.
pub async fn subscribe(instance: &Instance) -> Result<Events> {
    let (path, stream) = instance.connect_to_events().await?;
    Ok(Events {
        path,
        reader: BufReader::new(stream),
        line: Vec::new(),
    })
}

/// The events of a Hyprland instance, in the order Hyprland sent them.
/// Dropping it closes the connection.
#[derive(Debug)]
pub struct Events {
    path: PathBuf,
    reader: BufReader<UnixStream>,
    /// The line read so far, kept across calls of [`Events::next`].
    line: Vec<u8>,
}

impl Events {
    /// The next event. Keep calling it: Hyprland closes the connection of a
    /// program that falls 64 events behind.
    ///
    /// Dropping the future before it completes loses no event, so it can be
    /// one branch of a `tokio::select!`: the part of a line read so far stays
    /// in the line buffer, and the next call reads on from there (tokio
    /// 1.54.1, `AsyncBufReadExt::read_until`, section "Cancel safety",
    /// <https://docs.rs/tokio/1.54.1/tokio/io/trait.AsyncBufReadExt.html#method.read_until>,
    /// checked 2026-11-08).
    ///
    /// # Errors
    ///
    /// [`Error::EventsClosed`] when Hyprland closed the socket, and
    /// [`Error::ReadEvents`] when reading from it failed. An event that the
    /// close cut off does not arrive.
    pub async fn next(&mut self) -> Result<Event> {
        // The count restarts after a dropped call, so the newline tells
        // whether the line is whole.
        let _read_in_this_call: usize = self
            .reader
            .read_until(b'\n', &mut self.line)
            .await
            .map_err(|source| Error::ReadEvents {
                path: self.path.clone(),
                source,
            })?;
        let Some(line) = self.line.strip_suffix(b"\n") else {
            return Err(Error::EventsClosed {
                path: self.path.clone(),
            });
        };
        let event = line::read(line);
        self.line.clear();
        Ok(event)
    }
}

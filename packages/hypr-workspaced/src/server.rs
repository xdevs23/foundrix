//! The socket on which the daemon takes commands from its command line
//! client: one command line per connection, answered by one response line.

use std::convert::Infallible;
use std::fs;
use std::io;
use std::panic;
use std::path::Path;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinSet;
use tracing::error;

use crate::error::{Error, Result};
use crate::ipc::{Command, Response};

/// A command from a client of the daemon socket, with the channel for its
/// answer.
pub struct ClientRequest {
    pub command: Command,
    pub reply: oneshot::Sender<Response>,
}

/// Listen on the socket of the daemon at `path`, in place of a socket that
/// an earlier daemon left.
pub fn listen(path: &Path) -> Result<UnixListener> {
    let bind = || {
        match fs::remove_file(path) {
            Err(error) if error.kind() != io::ErrorKind::NotFound => return Err(error),
            _ => {}
        }
        UnixListener::bind(path)
    };
    bind().map_err(|source| Error::Listen {
        path: path.to_owned(),
        source,
    })
}

/// Answer the clients of the daemon socket, each in a task of its own, by
/// handing their commands to `requests`.
pub async fn serve(
    listener: UnixListener,
    requests: mpsc::Sender<ClientRequest>,
) -> Result<Infallible> {
    let mut clients = JoinSet::new();
    loop {
        tokio::select! {
            accepted = listener.accept() => match accepted {
                Ok((stream, _address)) => {
                    let _client = clients.spawn(handle_client(stream, requests.clone()));
                }
                Err(e) => error!("Failed to accept connection: {e}"),
            },
            Some(answered) = clients.join_next() => {
                if let Err(failed) = answered {
                    panic::resume_unwind(failed.into_panic());
                }
            }
        }
    }
}

async fn handle_client(stream: UnixStream, requests: mpsc::Sender<ClientRequest>) {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line = String::new();

    match reader.read_line(&mut line).await {
        Ok(0) => return,
        Ok(_) => {}
        Err(e) => {
            error!("Failed to read from client: {e}");
            return;
        }
    }

    let response = match line.trim().parse::<Command>() {
        Ok(command) => {
            let (reply, answer) = oneshot::channel();
            if requests
                .send(ClientRequest { command, reply })
                .await
                .is_ok()
            {
                match answer.await {
                    Ok(resp) => resp,
                    Err(_) => Response::Error("Internal error".to_string()),
                }
            } else {
                Response::Error("Daemon shutting down".to_string())
            }
        }
        Err(e) => Response::Error(e.to_string()),
    };

    let msg = format!("{response}\n");
    if let Err(e) = writer.write_all(msg.as_bytes()).await {
        error!("Failed to write response: {e}");
    }
}

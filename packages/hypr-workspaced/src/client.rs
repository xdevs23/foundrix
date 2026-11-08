use std::io;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;

use crate::error::{Error, Result};
use crate::ipc::{Command, Response, socket_path};

/// Send a command to the daemon, and print the data it answers with.
pub async fn send_command(command: Command) -> Result<()> {
    let path = socket_path()?;
    let stream = UnixStream::connect(&path)
        .await
        .map_err(|source| match source.kind() {
            io::ErrorKind::NotFound | io::ErrorKind::ConnectionRefused => {
                Error::DaemonNotRunning { path: path.clone() }
            }
            _ => Error::ConnectToDaemon {
                path: path.clone(),
                source,
            },
        })?;

    let (reader, mut writer) = stream.into_split();
    let exchange = async {
        writer.write_all(format!("{command}\n").as_bytes()).await?;
        writer.shutdown().await?;
        let mut response = String::new();
        // An empty answer does not read as a response below.
        let _answer_length: usize = BufReader::new(reader).read_line(&mut response).await?;
        Ok(response)
    };
    let response: String = exchange.await.map_err(Error::TalkToDaemon)?;

    match response.parse()? {
        Response::Ok => Ok(()),
        Response::Data(data) => {
            println!("{data}");
            Ok(())
        }
        Response::Error(message) => Err(Error::CommandFailed(message)),
    }
}

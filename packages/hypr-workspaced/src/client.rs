use std::io::ErrorKind;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;

use crate::error::{Error, Result};
use crate::ipc::{socket_path, Command, Response};

pub async fn send_command(command: Command) -> Result<()> {
    let path = socket_path();

    let stream = match UnixStream::connect(&path).await {
        Ok(s) => s,
        Err(e) if e.kind() == ErrorKind::NotFound || e.kind() == ErrorKind::ConnectionRefused => {
            return Err(Error::DaemonNotRunning);
        }
        Err(e) => return Err(e.into()),
    };

    let (reader, mut writer) = stream.into_split();

    let msg = format!("{command}\n");
    writer.write_all(msg.as_bytes()).await?;
    writer.shutdown().await?;

    let mut reader = BufReader::new(reader);
    let mut response = String::new();
    reader.read_line(&mut response).await?;

    let response: Response = response.parse().map_err(|e: crate::error::Error| e)?;

    match response {
        Response::Ok => Ok(()),
        Response::Error(msg) => Err(Error::Other(msg)),
    }
}

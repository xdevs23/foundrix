use std::io::ErrorKind;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;

use crate::error::{Error, Result};
use crate::ipc::{Command, Response, socket_path};

/// Send a command to the daemon, and print the data it answers with.
pub async fn send_command(command: Command) -> Result<()> {
    let stream = match UnixStream::connect(socket_path()).await {
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

    let mut response = String::new();
    // An empty answer does not read as a response below.
    let _answer_length: usize = BufReader::new(reader).read_line(&mut response).await?;

    match response.parse()? {
        Response::Ok => Ok(()),
        Response::Data(data) => {
            println!("{data}");
            Ok(())
        }
        Response::Error(msg) => Err(Error::Other(msg)),
    }
}

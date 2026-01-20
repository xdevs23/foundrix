use std::time::Duration;

use hyprland::event_listener::AsyncEventListener;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn};

use crate::error::Result;
use crate::ipc::{socket_path, Command, Response};
use crate::workspace::WorkspaceManager;

enum Event {
    Command(Command, tokio::sync::oneshot::Sender<Response>),
    MonitorChanged,
}

pub async fn run() -> Result<()> {
    let path = socket_path();

    if path.exists() {
        std::fs::remove_file(&path)?;
    }

    let listener = UnixListener::bind(&path)?;
    info!("Listening on {}", path.display());

    let (tx, mut rx) = mpsc::channel::<Event>(32);

    let tx_hyprland = tx.clone();
    let hyprland_task = tokio::spawn(async move {
        if let Err(e) = run_hyprland_listener(tx_hyprland).await {
            error!("Hyprland event listener failed: {e}");
        }
    });

    let tx_ipc = tx.clone();
    let ipc_task = tokio::spawn(async move {
        loop {
            match listener.accept().await {
                Ok((stream, _)) => {
                    let tx = tx_ipc.clone();
                    tokio::spawn(handle_client(stream, tx));
                }
                Err(e) => {
                    error!("Failed to accept connection: {e}");
                }
            }
        }
    });

    let manager = WorkspaceManager::new();

    info!("Performing initial workspace assignment");
    if let Err(e) = manager.assign_workspaces().await {
        error!("Initial workspace assignment failed: {e}");
    }

    loop {
        match rx.recv().await {
            Some(Event::Command(cmd, reply)) => {
                debug!("Received command: {cmd}");
                let result = handle_command(&manager, cmd).await;
                let response = match result {
                    Ok(()) => Response::Ok,
                    Err(e) => Response::Error(e.to_string()),
                };
                let _ = reply.send(response);
            }
            Some(Event::MonitorChanged) => {
                info!("Monitor configuration changed, reassigning workspaces");
                tokio::time::sleep(Duration::from_millis(500)).await;
                if let Err(e) = manager.assign_workspaces().await {
                    error!("Workspace reassignment failed: {e}");
                }
            }
            None => {
                warn!("Event channel closed");
                break;
            }
        }
    }

    hyprland_task.abort();
    ipc_task.abort();

    Ok(())
}

async fn run_hyprland_listener(tx: mpsc::Sender<Event>) -> Result<()> {
    let mut listener = AsyncEventListener::new();

    let tx_added = tx.clone();
    listener.add_monitor_added_handler(move |data| {
        let tx = tx_added.clone();
        Box::pin(async move {
            info!("Monitor added: {}", data.name);
            let _ = tx.send(Event::MonitorChanged).await;
        })
    });

    let tx_removed = tx.clone();
    listener.add_monitor_removed_handler(move |monitor_name| {
        let tx = tx_removed.clone();
        Box::pin(async move {
            info!("Monitor removed: {monitor_name}");
            let _ = tx.send(Event::MonitorChanged).await;
        })
    });

    listener.start_listener_async().await?;

    Ok(())
}

async fn handle_client(stream: UnixStream, tx: mpsc::Sender<Event>) {
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
        Ok(cmd) => {
            let (reply_tx, reply_rx) = tokio::sync::oneshot::channel();
            if tx.send(Event::Command(cmd, reply_tx)).await.is_ok() {
                match reply_rx.await {
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

async fn handle_command(manager: &WorkspaceManager, cmd: Command) -> Result<()> {
    match cmd {
        Command::Switch(ws) => manager.switch_virtual(ws).await,
        Command::MoveTo(ws) => manager.move_to_virtual(ws).await,
        Command::Navigate(dir) => manager.navigate(dir).await,
        Command::Collapse => manager.collapse().await,
        Command::Assign => manager.assign_workspaces().await,
    }
}

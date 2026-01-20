use std::time::Duration;

use hyprland::event_listener::AsyncEventListener;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{mpsc, watch};
use tracing::{debug, error, info, warn};

use crate::error::Result;
use crate::ipc::{socket_path, Command, Response};
use crate::workspace::WorkspaceManager;

enum Event {
    Command(Command, tokio::sync::oneshot::Sender<Response>),
    MonitorChanged,
}

/// Workspace sync state - uses watch channel so only latest value matters
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct SyncState {
    workspace_id: i32,
    generation: u64, // Incremented on each change to detect updates
}

pub async fn run() -> Result<()> {
    let path = socket_path();

    if path.exists() {
        std::fs::remove_file(&path)?;
    }

    let listener = UnixListener::bind(&path)?;
    info!("Listening on {}", path.display());

    // Channel for commands and monitor events (need reliable delivery)
    let (tx, mut rx) = mpsc::channel::<Event>(32);

    // Watch channel for workspace sync (only latest value matters)
    let (sync_tx, mut sync_rx) = watch::channel(SyncState {
        workspace_id: 0,
        generation: 0,
    });

    // Hyprland event listener with auto-restart
    let tx_hyprland = tx.clone();
    let hyprland_task = tokio::spawn(async move {
        loop {
            info!("Starting Hyprland event listener");
            if let Err(e) = run_hyprland_listener(tx_hyprland.clone(), sync_tx.clone()).await {
                error!("Hyprland event listener failed: {e}");
            }
            warn!("Hyprland listener stopped, restarting in 1s...");
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
    });

    // IPC server
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

    let mut manager = WorkspaceManager::new();
    let mut last_synced_generation: u64 = 0;

    info!("Performing initial workspace assignment");
    if let Err(e) = manager.assign_workspaces().await {
        error!("Initial workspace assignment failed: {e}");
    }

    loop {
        tokio::select! {
            // Handle commands and monitor events
            event = rx.recv() => {
                match event {
                    Some(Event::Command(cmd, reply)) => {
                        debug!("Received command: {cmd}");
                        let response = handle_command(&mut manager, cmd).await;
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

            // Handle workspace sync (watch channel - only latest matters)
            _ = sync_rx.changed() => {
                let state = *sync_rx.borrow();

                // Skip if we already processed this generation
                if state.generation <= last_synced_generation {
                    continue;
                }
                last_synced_generation = state.generation;

                if let Some(virtual_ws) = WorkspaceManager::virtual_from_workspace_id(state.workspace_id) {
                    debug!("Workspace changed to {} (virtual {}), syncing monitors", state.workspace_id, virtual_ws);
                    if let Err(e) = manager.sync_monitors(virtual_ws).await {
                        error!("Monitor sync failed: {e}");
                    }
                }
            }
        }
    }

    hyprland_task.abort();
    ipc_task.abort();

    Ok(())
}

async fn run_hyprland_listener(
    tx: mpsc::Sender<Event>,
    sync_tx: watch::Sender<SyncState>,
) -> Result<()> {
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

    // Use watch channel for workspace events - only latest value matters
    listener.add_workspace_changed_handler(move |data| {
        let sync_tx = sync_tx.clone();
        Box::pin(async move {
            debug!("Workspace changed event: id={}", data.id);
            // Update with new workspace, increment generation
            sync_tx.send_modify(|state| {
                state.workspace_id = data.id;
                state.generation = state.generation.wrapping_add(1);
            });
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

async fn handle_command(manager: &mut WorkspaceManager, cmd: Command) -> Response {
    let result = match cmd {
        Command::Switch(ws) => manager.switch_virtual(ws).await,
        Command::MoveTo(ws) => manager.move_to_virtual(ws).await,
        Command::Navigate(dir) => manager.navigate(dir).await,
        Command::Collapse => manager.collapse().await,
        Command::Assign => manager.assign_workspaces().await,
        Command::Pin(pattern) => manager.pin(&pattern),
        Command::Unpin(pattern) => manager.unpin(&pattern),
        Command::Pins => {
            let pins = manager.pins();
            return Response::Data(pins.join("\n"));
        }
    };

    match result {
        Ok(()) => Response::Ok,
        Err(e) => Response::Error(e.to_string()),
    }
}

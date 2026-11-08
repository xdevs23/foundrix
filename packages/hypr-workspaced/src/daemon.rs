use std::convert::Infallible;
use std::panic;

use hyproxide::Instance;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::{mpsc, oneshot};
use tokio::task::{JoinError, JoinSet};
use tracing::{debug, error, info, warn};
use tracing_subscriber::EnvFilter;
use tracing_subscriber::reload::Handle;

use crate::error::{Error, Result};
use crate::events;
use crate::ipc::{Command, Response, socket_path};
use crate::virtual_workspace::VirtualWorkspace;
use crate::workspace::WorkspaceManager;

type LogReloadHandle = Handle<EnvFilter, tracing_subscriber::Registry>;

/// A command from a client of the daemon socket, with the channel for its
/// answer.
struct ClientRequest {
    command: Command,
    reply: oneshot::Sender<Response>,
}

pub async fn run(log_handle: LogReloadHandle, on_reconnect_restart: Option<String>) -> Result<()> {
    let instance = Instance::from_environment()?;
    // Subscribe before the state is read for the first time, so no change
    // after that read is missed.
    let (mut changes, read_events) = events::subscribe(instance.clone()).await?;

    let path = socket_path();

    if path.exists() {
        std::fs::remove_file(&path)?;
    }

    let listener = UnixListener::bind(&path)?;
    info!("Listening on {}", path.display());

    // Signal systemd that we're ready to accept connections
    match sd_notify::notify(&[sd_notify::NotifyState::Ready]) {
        Ok(()) => info!("Notified systemd of readiness"),
        Err(e) => warn!("Failed to notify systemd of readiness: {e}"),
    }

    let (requests_tx, mut requests) = mpsc::channel::<ClientRequest>(32);

    // Both tasks run until they fail. Dropping the set stops them.
    let mut tasks = JoinSet::new();
    let _reader = tasks.spawn(read_events);
    let _server = tasks.spawn(serve_clients(listener, requests_tx));

    let mut manager = WorkspaceManager::new(instance);
    let mut last_synced_vspace: Option<VirtualWorkspace> = None;

    info!("Performing initial workspace assignment");
    if let Err(e) = manager.assign_workspaces().await {
        error!("Initial workspace assignment failed: {e}");
    }

    // Monitors are ready once the initial assignment has run. Prime pointer
    // focus now so the session does not start with every window unfocused
    // under input:follow_mouse (see WorkspaceManager::prime_focus).
    if let Err(e) = manager.prime_focus().await {
        warn!("Initial focus priming failed: {e}");
    }

    loop {
        tokio::select! {
            Some(ended) = tasks.join_next() => return Err(failure(ended)),

            Some(ClientRequest { command, reply }) = requests.recv() => {
                debug!("Received command: {command}");
                let response = handle_command(&mut manager, command, &log_handle).await;
                if reply.send(response).is_err() {
                    debug!("The client left before its answer");
                }
            }

            Ok(()) = changes.layout.changed() => {
                // Hyprland sends monitoraddedv2 once the monitor is arranged
                // and has its workspaces, and monitorremovedv2 once it is gone
                // (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/output/Monitor.cpp>,
                // onConnect and onDisconnect, checked 2026-11-08), so the
                // state read now has the change.
                info!("Monitor configuration changed, reassigning workspaces");
                if let Err(e) = manager.assign_workspaces().await {
                    error!("Workspace reassignment failed: {e}");
                }
                last_synced_vspace = None; // Reset on monitor change
            }

            Ok(()) = changes.resubscribed.changed() => {
                if let Some(service) = &on_reconnect_restart {
                    info!("Hyprland IPC reconnected, restarting service: {service}");
                    match restart_user_service(service).await {
                        Ok(()) => info!("Successfully restarted {service}"),
                        Err(e) => error!("Failed to restart {service}: {e}"),
                    }
                }
            }

            Ok(()) = changes.workspace.changed() => {
                let Some(workspace) = *changes.workspace.borrow() else {
                    continue;
                };
                let Some(vws) = VirtualWorkspace::from_hyprland_id(workspace) else {
                    continue;
                };

                // Skip if we already synced to this virtual workspace
                // (prevents feedback loop from our own workspace switches)
                if last_synced_vspace == Some(vws) {
                    debug!("Skipping sync for vspace {} (already synced)", vws);
                    continue;
                }

                debug!("Workspace changed to {workspace} (vspace {vws}), syncing monitors");
                if let Err(e) = manager.sync_monitors(workspace).await {
                    error!("Monitor sync failed: {e}");
                } else {
                    last_synced_vspace = Some(vws);
                }
            }
        }
    }
}

/// Why a task of the daemon, which runs until it fails, ended.
fn failure(ended: std::result::Result<Result<Infallible>, JoinError>) -> Error {
    match ended {
        Ok(Err(error)) => error,
        Ok(Ok(never)) => match never {},
        // Nothing cancels the tasks while the daemon runs, so only a panic
        // ends one this way.
        Err(failed) => panic::resume_unwind(failed.into_panic()),
    }
}

/// Answer the clients of the daemon socket, each in a task of its own.
async fn serve_clients(
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

/// Restart a systemd user service via D-Bus
async fn restart_user_service(service: &str) -> std::result::Result<(), zbus::Error> {
    let connection = zbus::Connection::session().await?;
    let proxy = zbus::proxy::Proxy::new(
        &connection,
        "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager",
    )
    .await?;

    // RestartUnit(name: s, mode: s) -> job: o
    let _job: zbus::OwnedObjectPath = proxy.call("RestartUnit", &(service, "replace")).await?;

    Ok(())
}

async fn handle_command(
    manager: &mut WorkspaceManager,
    cmd: Command,
    log_handle: &LogReloadHandle,
) -> Response {
    let result = match cmd {
        Command::Switch(ws) => match VirtualWorkspace::new(ws) {
            Ok(vws) => manager.switch_virtual(vws).await,
            Err(e) => Err(e),
        },
        Command::MoveTo(ws) => match VirtualWorkspace::new(ws) {
            Ok(vws) => manager.move_to_virtual(vws).await,
            Err(e) => Err(e),
        },
        Command::Navigate(dir) => manager.navigate(dir).await,
        Command::Collapse(mode) => manager.collapse(mode).await,
        Command::Swap(dir) => manager.swap_monitor(dir).await,
        Command::Assign => manager.assign_workspaces().await,
        Command::Pin(pattern) => manager.pin(&pattern),
        Command::Unpin(pattern) => manager.unpin(&pattern),
        Command::Pins => return Response::Data(manager.pins().join("\n")),
        Command::Debug(enabled) => {
            let level = if enabled { "debug" } else { "info" };
            match log_handle.reload(EnvFilter::new(level)) {
                Ok(()) => {
                    info!("Log level set to {level}");
                    return Response::Ok;
                }
                Err(e) => return Response::Error(format!("Failed to set log level: {e}")),
            }
        }
    };

    match result {
        Ok(()) => Response::Ok,
        Err(e) => Response::Error(e.to_string()),
    }
}

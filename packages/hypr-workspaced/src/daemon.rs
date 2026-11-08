use std::convert::Infallible;
use std::panic;

use hypr_workspaced::systemd;
use hyproxide::Instance;
use hyproxide::workspace::WorkspaceId;
use tokio::sync::mpsc;
use tokio::task::{JoinError, JoinSet};
use tracing::{debug, error, info, warn};
use tracing_subscriber::EnvFilter;
use tracing_subscriber::reload::Handle;

use crate::error::{Error, Result};
use crate::events;
use crate::ipc::{Command, DebugLogging, Response, socket_path};
use crate::server::{self, ClientRequest};
use crate::virtual_workspace::VirtualWorkspace;
use crate::workspace::WorkspaceManager;

type LogReloadHandle = Handle<EnvFilter, tracing_subscriber::Registry>;

/// Run the daemon until Hyprland cannot be reached anymore.
pub async fn run(log_handle: LogReloadHandle, restarted_service: Option<String>) -> Result<()> {
    let instance = Instance::from_environment()?;
    // Subscribe before the state is read for the first time, so no change
    // after that read is missed.
    let (mut changes, read_events) = events::subscribe(instance.clone()).await?;

    let path = socket_path()?;
    let listener = server::listen(&path)?;
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
    let _server = tasks.spawn(server::serve(listener, requests_tx));

    let mut daemon = Daemon::start(instance, log_handle, restarted_service).await;

    loop {
        tokio::select! {
            Some(ended) = tasks.join_next() => return Err(failure(ended)),
            Some(request) = requests.recv() => daemon.on_request(request).await,
            Ok(()) = changes.layout.changed() => daemon.on_layout_changed().await,
            Ok(()) = changes.resubscribed.changed() => daemon.on_resubscribed().await,
            Ok(()) = changes.workspace.changed() => {
                let workspace = *changes.workspace.borrow();
                daemon.on_workspace_changed(workspace).await;
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

/// What the daemon keeps between the events and commands it acts on, one
/// at a time.
struct Daemon {
    manager: WorkspaceManager,
    /// The virtual workspace the last complete sync showed on every monitor.
    last_synced: Option<VirtualWorkspace>,
    /// The user service to restart when the event connection was lost.
    restarted_service: Option<String>,
    log_handle: LogReloadHandle,
}

impl Daemon {
    /// Assign the workspaces to the monitors, and focus the window under the
    /// cursor.
    async fn start(
        instance: Instance,
        log_handle: LogReloadHandle,
        restarted_service: Option<String>,
    ) -> Self {
        let mut manager = WorkspaceManager::new(instance);

        info!("Performing initial workspace assignment");
        if let Err(e) = manager.assign_workspaces().await {
            error!("Initial workspace assignment failed: {e}");
        }

        // Monitors are ready once the initial assignment has run. Prime
        // pointer focus now so the session does not start with every window
        // unfocused under input:follow_mouse (see
        // WorkspaceManager::prime_focus).
        if let Err(e) = manager.prime_focus().await {
            warn!("Initial focus priming failed: {e}");
        }

        Self {
            manager,
            last_synced: None,
            restarted_service,
            log_handle,
        }
    }

    async fn on_request(&mut self, ClientRequest { command, reply }: ClientRequest) {
        debug!("Received command: {command}");
        let response = self.run(command).await;
        if reply.send(response).is_err() {
            debug!("The client left before its answer");
        }
    }

    async fn on_layout_changed(&mut self) {
        // Hyprland sends monitoraddedv2 once the monitor is arranged and has
        // its workspaces, and monitorremovedv2 once it is gone
        // (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/output/Monitor.cpp>,
        // onConnect and onDisconnect, checked 2026-11-08), so the state read
        // now has the change.
        info!("Monitor configuration changed, reassigning workspaces");
        if let Err(e) = self.manager.assign_workspaces().await {
            error!("Workspace reassignment failed: {e}");
        }
        self.last_synced = None;
    }

    async fn on_resubscribed(&self) {
        if let Some(service) = &self.restarted_service {
            info!("Hyprland IPC reconnected, restarting service: {service}");
            match systemd::restart(service).await {
                Ok(()) => info!("Successfully restarted {service}"),
                Err(e) => error!("Failed to restart {service}: {e}"),
            }
        }
    }

    /// Show the virtual workspace of `workspace`, the numbered workspace that
    /// got focus last, on every monitor.
    async fn on_workspace_changed(&mut self, workspace: Option<WorkspaceId>) {
        let Some(workspace) = workspace else {
            return;
        };
        let Some(vws) = VirtualWorkspace::from_hyprland_id(workspace) else {
            return;
        };

        // Skip if we already synced to this virtual workspace
        // (prevents feedback loop from our own workspace switches)
        if self.last_synced == Some(vws) {
            debug!("Skipping sync for vspace {} (already synced)", vws);
            return;
        }

        debug!("Workspace changed to {workspace} (vspace {vws}), syncing monitors");
        // Only a sync that showed the workspace everywhere stops the next
        // event of the same virtual workspace from syncing again.
        self.last_synced = match self.manager.sync_monitors(vws, workspace).await {
            Ok(()) => Some(vws),
            Err(e) => {
                error!("Monitor sync failed: {e}");
                None
            }
        };
    }

    /// Run a command of a client, and return the answer for it.
    async fn run(&mut self, command: Command) -> Response {
        let manager = &mut self.manager;
        let result = match command {
            Command::Switch(workspace) => manager.switch_virtual(workspace).await,
            Command::MoveTo(workspace) => manager.move_to_virtual(workspace).await,
            Command::Navigate(dir) => manager.navigate(dir).await,
            Command::Collapse(mode) => manager.collapse(mode).await,
            Command::Swap(dir) => manager.swap_monitor(dir).await,
            Command::Assign => manager.assign_workspaces().await,
            Command::Pin(pattern) => manager.pin(&pattern),
            Command::Unpin(pattern) => manager.unpin(&pattern),
            Command::Pins => return Response::Data(manager.pins().join("\n")),
            Command::Debug(logging) => self.set_debug_logging(logging),
        };

        match result {
            Ok(()) => Response::Ok,
            Err(e) => Response::Error(e.to_string()),
        }
    }

    fn set_debug_logging(&self, logging: DebugLogging) -> Result<()> {
        let level = match logging {
            DebugLogging::On => "debug",
            DebugLogging::Off => "info",
        };
        self.log_handle
            .reload(EnvFilter::new(level))
            .map_err(Error::LogLevel)
            .inspect(|()| info!("Log level set to {level}"))
    }
}

//! The daemon against a Hyprland 0.57 with two outputs, which the test starts
//! for itself.
//!
//! Hyprland takes over the display of the machine, so this test runs only in
//! the NixOS VM check `hypr-workspaced-end-to-end`. It runs the daemon
//! `hypr-workspaced` from PATH, reaches the systemd user manager through
//! `DBUS_SESSION_BUS_ADDRESS`, and expects the user service named by
//! `RESTARTED_SERVICE`, which stands in for the top bar. A step waits for its
//! events without a time limit of its own, in whatever order they arrive, and
//! prints what it waits for and every event that arrives.

use std::env;
use std::future;
use std::pin::Pin;

use hypr_workspaced::systemd::{JobMode, JobRemovedStream, JobResult, ManagerProxy, UnitProxy};
use hyproxide::dispatch::command::{self, Command, OutputBackend};
use hyproxide::dispatch::{self, Focus, WindowSelector, rule, window, workspace};
use hyproxide::event::{self, DATA_LIMIT, Event, Events};
use hyproxide::workspace::{WorkspaceAddress, WorkspaceId};
use hyproxide::{Instance, Word, query};
use hyproxide_testing::{
    HyprlandEnvironment, TempDirectory, open_connections_to, read_until, wait_for_ready,
    with_hyprland_environment,
};
use tokio::net::UnixDatagram;
use tokio::process::Child;
use zbus::Connection;
use zbus::export::futures_core::Stream as _;
use zbus::proxy::CacheProperties;

/// The output the test adds next to the one of the machine.
const SECOND_OUTPUT: &str = "HYPR-WORKSPACED-1";

fn id(number: u32) -> WorkspaceId {
    WorkspaceId::try_from(number).unwrap()
}

fn focus(workspace: u32) -> Focus {
    Focus::Workspace {
        workspace: id(workspace).into(),
        on_current_monitor: false,
    }
}

fn changed_to(workspace: u32) -> impl Fn(&Event) -> bool {
    move |event| {
        matches!(event, Event::WorkspaceChanged(changed)
            if changed.address == WorkspaceAddress::Numbered(id(workspace)))
    }
}

#[tokio::test]
async fn the_daemon_keeps_two_outputs_in_step_and_restarts_the_service_after_a_lost_connection() {
    with_hyprland_environment(|instance, environment| async move {
        let instance = &instance;
        let service = Service::from_environment().await;
        let mut jobs = service.finished_jobs().await;
        service.start().await;
        assert_eq!(
            next_job(&mut jobs).await,
            JobResult::Done,
            "starting {}",
            service.name
        );
        let started = service.invocation().await;

        let first_output = prepare_two_outputs(instance).await;
        let mut daemon = Daemon::start(environment, &service.name).await;
        let mut events = event::subscribe(instance).await.unwrap();
        assert_shown(instance, &first_output, [1, 11]).await;

        open_and_close_a_special_workspace(instance, &mut events).await;
        open_and_close_a_window_with_a_comma_in_its_title(instance, &mut events).await;
        switch(instance, &mut events, &daemon, 3, 13).await;
        assert_shown(instance, &first_output, [3, 13]).await;
        switch(instance, &mut events, &daemon, 15, 5).await;
        assert_shown(instance, &first_output, [5, 15]).await;
        daemon.assert_running();
        assert_eq!(
            service.invocation().await,
            started,
            "the daemon restarted {}",
            service.name
        );

        // Hyprland closes the event socket of a program that falls 64 events
        // behind (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/ipc/s2/Unix.cpp>,
        // `MAX_QUEUED_EVENTS`, checked 2026-11-08). The test reads no events
        // meanwhile either, so it drops its own stream first.
        drop(events);
        daemon.signal(Signal::Stop).await;
        let dropping = flood_until_dropped(instance).await;
        daemon.signal(Signal::Continue).await;
        assert_eq!(
            next_job(&mut jobs).await,
            JobResult::Done,
            "restarting {}",
            service.name
        );
        let restarted = service.invocation().await;
        assert_ne!(restarted, started);

        // Twice the events that dropped the stopped daemon, so the burst
        // drops a daemon that stops reading while it is busy.
        send_a_burst_while_busy(instance, &daemon, 2 * dropping).await;
        assert_eq!(
            service.invocation().await,
            restarted,
            "the daemon restarted {} after the burst",
            service.name
        );

        let mut events = event::subscribe(instance).await.unwrap();
        switch(instance, &mut events, &daemon, 7, 17).await;
        assert_shown(instance, &first_output, [7, 17]).await;
        daemon.assert_running();
        daemon.stop().await;
    })
    .await;
}

/// Add the second output, and show workspace 1 on the first output and 11
/// on the second, the workspaces the daemon assigns to them. The daemon
/// then starts with nothing to switch, so no switch of its own crosses the
/// steps of the test. Returns the name of the first output.
async fn prepare_two_outputs(instance: &Instance) -> String {
    let monitors = query::monitors(instance).await.unwrap();
    let [first] = monitors.as_slice() else {
        panic!("expected one output, found {monitors:?}")
    };
    let create = Command::CreateOutput {
        backend: OutputBackend::Headless,
        name: Some(Word::try_from(SECOND_OUTPUT).unwrap()),
    };
    command::run(instance, &create).await.unwrap();
    let eleven = rule::workspace_rule(id(11)).monitor(SECOND_OUTPUT);
    rule::apply(instance, &eleven).await.unwrap();
    dispatch::dispatch(instance, focus(11)).await.unwrap();
    dispatch::dispatch(instance, focus(1)).await.unwrap();
    first.name.clone()
}

/// Assert the workspaces the first and the second output show.
async fn assert_shown(instance: &Instance, first_output: &str, expected: [u32; 2]) {
    let shown = |output: &str, monitors: &[query::Monitor]| {
        monitors
            .iter()
            .find(|monitor| monitor.name == output)
            .and_then(|monitor| monitor.active_workspace.address.id())
    };
    let monitors = query::monitors(instance).await.unwrap();
    let [first, second] = expected.map(id);
    assert_eq!(
        [
            shown(first_output, &monitors),
            shown(SECOND_OUTPUT, &monitors)
        ],
        [Some(first), Some(second)],
        "{monitors:#?}"
    );
}

/// Show workspace `to`, and wait until the daemon showed `mirrored` on the
/// other output and finished the sync, which focuses `to` again.
async fn switch(instance: &Instance, events: &mut Events, daemon: &Daemon, to: u32, mirrored: u32) {
    dispatch::dispatch(instance, focus(to)).await.unwrap();
    let awaited = format!("workspace {mirrored}");
    let _received = read_until(events, &awaited, |received| {
        received.iter().any(changed_to(mirrored))
    })
    .await;
    // Only the sync shows `mirrored`, so the daemon handles it now.
    daemon.finish_current_event().await;
}

async fn open_and_close_a_special_workspace(instance: &Instance, events: &mut Events) {
    let shown = |event: &Event| {
        matches!(event, Event::SpecialWorkspaceChanged { workspace, .. }
            if workspace.address == WorkspaceAddress::Special("scratch".into()))
    };
    let hidden = |event: &Event| {
        matches!(event, Event::SpecialWorkspaceChanged { workspace, .. }
            if workspace.address == WorkspaceAddress::None)
    };
    dispatch::dispatch(instance, workspace::toggle_special(Some("scratch")))
        .await
        .unwrap();
    let _received = read_until(events, "special:scratch to open", |received| {
        received.iter().any(shown)
    })
    .await;
    dispatch::dispatch(instance, workspace::toggle_special(Some("scratch")))
        .await
        .unwrap();
    let _received = read_until(events, "special:scratch to close", |received| {
        received.iter().any(hidden)
    })
    .await;
}

async fn open_and_close_a_window_with_a_comma_in_its_title(
    instance: &Instance,
    events: &mut Events,
) {
    let foot = "foot --title 'hypr-workspaced, end to end' --hold true";
    dispatch::dispatch(instance, dispatch::exec_cmd(foot))
        .await
        .unwrap();
    let opened = |received: &[Event]| {
        received.iter().find_map(|event| match event {
            Event::WindowOpenedUndivided { window, .. } => Some(*window),
            _ => None,
        })
    };
    let received = read_until(events, "the window to open", |received| {
        opened(received).is_some()
    })
    .await;
    let window = opened(&received).unwrap();

    let close = window::close().window(WindowSelector::Address(window));
    dispatch::dispatch(instance, close).await.unwrap();
    let _received = read_until(events, "the window to close", |received| {
        received.contains(&Event::WindowClosed(window))
    })
    .await;
}

/// Send a `custom` event with the most data Hyprland sends in one event.
async fn send_full_event(instance: &Instance) {
    let data = "x".repeat(DATA_LIMIT);
    dispatch::dispatch(instance, dispatch::event(&data))
        .await
        .unwrap();
}

/// Send events until Hyprland closed every connection to its event socket,
/// and return how many it took. The connection of the stopped daemon closes
/// once the socket buffer of the kernel is full and 64 more events wait for
/// it, the connection of the test once Hyprland sees that the test closed
/// it.
async fn flood_until_dropped(instance: &Instance) -> usize {
    let socket = instance.event_socket();
    assert!(
        !open_connections_to(&socket).is_empty(),
        "the daemon has no connection to {}",
        socket.display()
    );
    eprintln!(
        "sending events until Hyprland closed every connection to {}",
        socket.display()
    );
    let mut sent = 0;
    while !open_connections_to(&socket).is_empty() {
        send_full_event(instance).await;
        sent += 1;
    }
    eprintln!("Hyprland closed every connection after {sent} events");
    sent
}

/// Send `count` events while the daemon runs `assign`, and assert that
/// Hyprland kept the connection of the daemon open meanwhile.
async fn send_a_burst_while_busy(instance: &Instance, daemon: &Daemon, count: usize) {
    let socket = instance.event_socket();
    let connections = open_connections_to(&socket);
    assert_eq!(
        connections.len(),
        1,
        "expected only the connection of the daemon to {}",
        socket.display()
    );
    eprintln!("sending {count} events while the daemon assigns the workspaces");
    let burst = async {
        for _ in 0..count {
            send_full_event(instance).await;
        }
    };
    let ((), ()) = tokio::join!(burst, daemon.run("assign"));
    assert_eq!(
        open_connections_to(&socket),
        connections,
        "Hyprland closed the connection of the daemon during the burst"
    );
}

/// The signals the test sends the daemon.
#[derive(Debug, Clone, Copy)]
enum Signal {
    Stop,
    Continue,
}

impl Signal {
    /// The name of the signal for `kill -s`.
    fn as_str(self) -> &'static str {
        match self {
            Signal::Stop => "STOP",
            Signal::Continue => "CONT",
        }
    }
}

/// The daemon, started as the desktop service starts it.
struct Daemon {
    process: Child,
    environment: HyprlandEnvironment,
    _state: TempDirectory,
}

impl Daemon {
    /// Start the daemon, wait until it reports to be ready, and run its
    /// `assign` command, as the desktop service does after the start. The
    /// command returns once the daemon handled everything before it.
    async fn start(environment: HyprlandEnvironment, service: &str) -> Self {
        let state = TempDirectory::create();
        let notify_socket = state.path().join("notify.sock");
        let notifications = UnixDatagram::bind(&notify_socket).unwrap();
        let mut process = environment
            .apply(&mut tokio::process::Command::new("hypr-workspaced"))
            .args(["daemon", "--on-hypr-ipc-reconnect-restart", service])
            // The registry of monitors.
            .env("XDG_STATE_HOME", state.path())
            .env("NOTIFY_SOCKET", &notify_socket)
            .kill_on_drop(true)
            .spawn()
            .expect("starting hypr-workspaced from PATH failed");
        tokio::select! {
            () = wait_for_ready(&notifications) => {}
            exited = process.wait() => panic!("the daemon exited before it was ready: {exited:?}"),
        }

        let daemon = Self {
            process,
            environment,
            _state: state,
        };
        daemon.run("assign").await;
        daemon
    }

    /// Run a command of the client `hypr-workspaced`, and assert that it
    /// succeeded.
    async fn run(&self, command: &str) {
        let status = self
            .environment
            .apply(&mut tokio::process::Command::new("hypr-workspaced"))
            .arg(command)
            .status()
            .await
            .unwrap();
        assert!(status.success(), "hypr-workspaced {command}: {status}");
    }

    /// Wait until the daemon finished the event it handles. It handles one
    /// event or command at a time, so it answers `pins` only after that.
    async fn finish_current_event(&self) {
        self.run("pins").await;
    }

    fn assert_running(&mut self) {
        assert_eq!(self.process.try_wait().unwrap(), None, "the daemon exited");
    }

    async fn signal(&self, signal: Signal) {
        let pid = self.process.id().unwrap().to_string();
        let sent = tokio::process::Command::new("kill")
            .args(["-s", signal.as_str(), &pid])
            .status()
            .await
            .unwrap();
        assert!(sent.success(), "kill -s {signal:?}: {sent}");
    }

    async fn stop(mut self) {
        self.process.kill().await.unwrap();
    }
}

/// The user service that stands in for the top bar, through the systemd
/// user manager.
struct Service {
    name: String,
    connection: Connection,
    manager: ManagerProxy<'static>,
}

impl Service {
    async fn from_environment() -> Self {
        let name = env::var("RESTARTED_SERVICE")
            .expect("RESTARTED_SERVICE names the service the daemon restarts");
        let connection = Connection::session().await.unwrap();
        let manager = ManagerProxy::new(&connection).await.unwrap();
        // The manager sends JobRemoved only to subscribed clients.
        manager.subscribe().await.unwrap();
        Self {
            name,
            connection,
            manager,
        }
    }

    /// The jobs of the service, as they finish.
    async fn finished_jobs(&self) -> JobRemovedStream {
        // The third argument of JobRemoved is the name of the unit.
        self.manager
            .receive_job_removed_with_args(&[(2, &self.name)])
            .await
            .unwrap()
    }

    async fn start(&self) {
        let _job = self
            .manager
            .start_unit(&self.name, JobMode::Replace)
            .await
            .unwrap();
    }

    /// The id systemd gives each run of the service.
    async fn invocation(&self) -> Vec<u8> {
        let unit = self.manager.get_unit(&self.name).await.unwrap();
        UnitProxy::builder(&self.connection)
            .path(unit)
            .cache_properties(CacheProperties::No)
            .build()
            .await
            .unwrap()
            .invocation_id()
            .await
            .unwrap()
    }
}

/// The result of the next finished job of the service.
async fn next_job(jobs: &mut JobRemovedStream) -> JobResult {
    eprintln!("waiting for a job of the service to finish");
    let removed = future::poll_fn(|context| Pin::new(&mut *jobs).poll_next(context))
        .await
        .expect("the session bus closed");
    let finished = removed.args().unwrap();
    eprintln!(
        "job {} {:?} of {}: {:?}",
        finished.id, finished.job, finished.unit, finished.result
    );
    finished.result
}

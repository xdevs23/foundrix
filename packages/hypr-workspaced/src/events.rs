//! The events of Hyprland that the daemon acts on.
//!
//! Hyprland drops a program that falls 64 events behind (see the
//! `hyproxide::event` documentation). The reader here never waits for the
//! daemon: it replaces the latest value of each kind of change in a watch
//! channel and reads on, so a burst of events does not leave it behind while
//! the daemon switches workspaces.

use std::convert::Infallible;

use hyproxide::Instance;
use hyproxide::event::{self, Event, Events};
use hyproxide::workspace::WorkspaceId;
use tokio::sync::watch;
use tracing::{debug, info, warn};

use crate::error::Result;

/// The events that change the monitors, by the name of their line.
const LAYOUT_EVENTS: [&[u8]; 3] = [b"monitoraddedv2", b"monitorremovedv2", b"configreloaded"];

/// The event of a change of the workspace, by the name of its line.
const WORKSPACE_EVENT: &[u8] = b"workspacev2";

/// The changes the daemon acts on, each as its latest value.
pub struct Changes {
    /// The numbered workspace that got focus last.
    pub workspace: watch::Receiver<Option<WorkspaceId>>,
    /// Monitors were added or removed, the configuration was reloaded, or
    /// events were lost.
    pub layout: watch::Receiver<()>,
    /// The event socket closed or failed, and the reader subscribed again.
    pub resubscribed: watch::Receiver<()>,
}

/// The sending side of [`Changes`], which the reader owns.
struct Recorder {
    workspace: watch::Sender<Option<WorkspaceId>>,
    layout: watch::Sender<()>,
    resubscribed: watch::Sender<()>,
}

/// Subscribe to the events of `instance`. Returns the changes, and the
/// reader that records them, which runs until Hyprland cannot be reached
/// anymore.
pub async fn subscribe(
    instance: Instance,
) -> Result<(Changes, impl Future<Output = Result<Infallible>>)> {
    let events = event::subscribe(&instance).await?;
    let (recorder, changes) = Recorder::new();
    Ok((changes, recorder.read(instance, events)))
}

impl Recorder {
    fn new() -> (Self, Changes) {
        let (workspace, workspace_changes) = watch::channel(None);
        let (layout, layout_changes) = watch::channel(());
        let (resubscribed, resubscriptions) = watch::channel(());
        let recorder = Self {
            workspace,
            layout,
            resubscribed,
        };
        let changes = Changes {
            workspace: workspace_changes,
            layout: layout_changes,
            resubscribed: resubscriptions,
        };
        (recorder, changes)
    }

    /// Record the events of Hyprland. When the event socket closes or fails,
    /// subscribe again; fail when that fails, as Hyprland is gone then.
    async fn read(self, instance: Instance, mut events: Events) -> Result<Infallible> {
        loop {
            match events.next().await {
                Ok(event) => self.record(event),
                Err(closed) => {
                    warn!("{closed}");
                    events = event::subscribe(&instance).await?;
                    info!("Subscribed to the events of Hyprland again");
                    // The events in between are lost: read the state anew.
                    self.layout.send_replace(());
                    self.resubscribed.send_replace(());
                }
            }
        }
    }

    fn record(&self, event: Event) {
        match event {
            Event::WorkspaceChanged(workspace) => {
                debug!("Workspace changed event: {}", workspace.address);
                if let Some(id) = workspace.address.id() {
                    self.workspace.send_modify(|latest| *latest = Some(id));
                }
            }
            Event::MonitorAdded { name, .. } => {
                info!("Monitor added: {name}");
                self.layout.send_replace(());
            }
            Event::MonitorRemoved { name, .. } => {
                info!("Monitor removed: {name}");
                self.layout.send_replace(());
            }
            Event::ConfigReloaded => {
                info!("Hyprland config reloaded, reassigning workspaces");
                self.layout.send_replace(());
            }
            // hyproxide reads a line it cannot read exactly as unknown, also
            // one of an event the daemon acts on. A reassignment reads the
            // monitors anew, so it does no harm when nothing changed.
            Event::Unknown { name, data } if LAYOUT_EVENTS.contains(&name.as_slice()) => {
                warn_unread(&name, &data);
                self.layout.send_replace(());
            }
            Event::Unknown { name, data } if name == WORKSPACE_EVENT => warn_unread(&name, &data),
            // Other events, unknown ones too, change nothing the daemon keeps
            // in step.
            _ => {}
        }
    }
}

/// Report an event the daemon acts on that arrived in a form hyproxide
/// does not read.
fn warn_unread(name: &[u8], data: &[u8]) {
    warn!(
        "Hyprland sent {} in a form hyproxide does not read: {}",
        name.escape_ascii(),
        data.escape_ascii()
    );
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::Path;

    use hyproxide::event::DATA_LIMIT;
    use hyproxide_testing::TempDirectory;
    use tokio::io::AsyncWriteExt as _;
    use tokio::net::{UnixListener, UnixStream};
    use tokio::task::JoinHandle;

    use super::*;
    use crate::error::Error;

    fn id(number: u32) -> WorkspaceId {
        WorkspaceId::try_from(number).unwrap()
    }

    /// The event socket of a fake Hyprland in `directory`.
    fn listen(directory: &Path) -> UnixListener {
        UnixListener::bind(directory.join(".socket2.sock")).unwrap()
    }

    /// Subscribe to the fake Hyprland in `directory`, and return the
    /// changes, the running reader, and the connection Hyprland writes
    /// events into.
    async fn subscribe_to(
        directory: &Path,
        listener: &UnixListener,
    ) -> (Changes, JoinHandle<Result<Infallible>>, UnixStream) {
        let (subscribed, accepted) =
            tokio::join!(subscribe(Instance::at(directory)), listener.accept());
        let (changes, reader) = subscribed.unwrap();
        let (connection, _address) = accepted.unwrap();
        (changes, tokio::spawn(reader), connection)
    }

    /// Write lines to the event socket the way Hyprland does.
    async fn send(connection: &mut UnixStream, lines: &[&str]) {
        for line in lines {
            connection
                .write_all(format!("{line}\n").as_bytes())
                .await
                .unwrap();
        }
    }

    /// Events that change nothing the daemon keeps in step.
    const UNRELATED: [&str; 6] = [
        "activespecialv2>>special:scratch,special:scratch,HEADLESS-2",
        "workspacev2>>web,web",
        "destroyworkspacev2>>special:scratch,special:scratch",
        "openwindow>>5731,6,foot,hypr-workspaced, test",
        "activewindow>>foot,hypr-workspaced, test",
        "somethingnew>>with,data",
    ];

    #[tokio::test]
    async fn the_reader_reads_on_and_subscribes_again_only_when_the_socket_closes() {
        let directory = TempDirectory::create();
        let listener = listen(directory.path());
        let (mut changes, reading, mut first) = subscribe_to(directory.path(), &listener).await;

        // Events that change nothing the daemon keeps in step, then a change
        // of the workspace: the reader got past all of them once it arrives.
        send(&mut first, &UNRELATED).await;
        send(&mut first, &["workspacev2>>13,13"]).await;
        changes.workspace.changed().await.unwrap();
        assert_eq!(*changes.workspace.borrow(), Some(id(13)));
        assert!(!changes.layout.has_changed().unwrap());

        // The same events, then a change of the configuration: none of them
        // changed the workspace.
        send(&mut first, &UNRELATED).await;
        send(&mut first, &["configreloaded>>"]).await;
        changes.layout.changed().await.unwrap();
        assert!(!changes.workspace.has_changed().unwrap());
        assert_eq!(*changes.workspace.borrow(), Some(id(13)));

        for line in [
            "monitoraddedv2>>2,HEADLESS-2,",
            "monitorremovedv2>>2,HEADLESS-2,",
            "configreloaded>>",
            // A monitor id that is no number: hyproxide reads the line as
            // unknown.
            "monitoraddedv2>>x,y",
        ] {
            send(&mut first, &[line]).await;
            changes.layout.changed().await.unwrap();
        }
        assert!(!changes.resubscribed.has_changed().unwrap());

        drop(first);
        let (mut second, _address) = listener.accept().await.unwrap();
        changes.resubscribed.changed().await.unwrap();
        assert!(changes.layout.has_changed().unwrap());

        send(&mut second, &["workspacev2>>4,4"]).await;
        changes.workspace.changed().await.unwrap();
        assert_eq!(*changes.workspace.borrow(), Some(id(4)));

        // Hyprland is gone: its event socket closes and is removed.
        drop(listener);
        fs::remove_file(directory.path().join(".socket2.sock")).unwrap();
        drop(second);
        let ended = reading.await.unwrap();
        assert!(
            matches!(
                ended,
                Err(Error::Hyprland(hyproxide::Error::Connect { .. }))
            ),
            "{ended:?}"
        );
    }

    /// How many bytes the kernel holds for a Unix stream connection that is
    /// not read: the default size of its send buffer.
    fn socket_buffer() -> usize {
        fs::read_to_string("/proc/sys/net/core/wmem_default")
            .unwrap()
            .trim()
            .parse()
            .unwrap()
    }

    #[tokio::test]
    async fn the_reader_drains_a_burst_while_the_daemon_reads_no_change() {
        let directory = TempDirectory::create();
        let listener = listen(directory.path());
        let (mut changes, _reading, mut connection) =
            subscribe_to(directory.path(), &listener).await;

        // Twice what the kernel holds for a connection that is not read, in
        // lines as long as Hyprland writes them: a write waits until the
        // reader drains the connection.
        let line = format!("custom>>{}", "x".repeat(DATA_LIMIT));
        let lines = 2 * socket_buffer() / line.len() + 1;
        for _ in 0..lines {
            send(&mut connection, &[&line]).await;
        }
        send(&mut connection, &["workspacev2>>13,13"]).await;

        changes.workspace.changed().await.unwrap();
        assert_eq!(*changes.workspace.borrow(), Some(id(13)));
        assert!(!changes.resubscribed.has_changed().unwrap());
    }
}

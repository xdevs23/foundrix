//! Events from a Hyprland 0.57 started by each test for itself.
//!
//! Hyprland takes over the display of the machine, so these tests run one at
//! a time, and only in the NixOS VM check `hyproxide-live`. A step waits for
//! its events without a time limit of its own. It prints what it waits for
//! and every event that arrives, so the log of a run that hangs shows which
//! event is missing.

#[path = "support/hyprland.rs"]
mod hyprland;
mod support;

use hyproxide::dispatch::command::{self, Command, OutputBackend};
use hyproxide::dispatch::{self, Focus, WindowSelector, window, workspace};
use hyproxide::event::{self, Event, Events};
use hyproxide::workspace::{WorkspaceAddress, WorkspaceId, WorkspaceRef};
use hyproxide::{Instance, Word, query};

use hyprland::with_hyprland;

/// Read events until `done` holds for the events read so far, and return
/// them.
async fn read_until(
    events: &mut Events,
    awaited: &str,
    done: impl Fn(&[Event]) -> bool,
) -> Vec<Event> {
    eprintln!("waiting for {awaited}");
    let mut received = Vec::new();
    while !done(&received) {
        let event = events.next().await.expect("the event stream ended");
        eprintln!("received {event:?}");
        received.push(event);
    }
    received
}

fn assert_all_known(received: &[Event]) {
    assert!(
        !received
            .iter()
            .any(|event| matches!(event, Event::Unknown { .. })),
        "{received:?}"
    );
}

fn unrenamed(address: WorkspaceAddress) -> WorkspaceRef {
    WorkspaceRef {
        name: address.to_string(),
        address,
    }
}

#[tokio::test]
async fn events_arrive_typed_and_the_stream_goes_on() {
    with_hyprland(|instance| async move {
        let instance = &instance;
        let monitors = query::monitors(instance).await.unwrap();
        let mut events = event::subscribe(instance).await.unwrap();

        open_and_close_a_special_workspace(instance, &mut events, &monitors[0].name).await;
        change_the_workspace(instance, &mut events).await;
        add_and_remove_an_output(instance, &mut events).await;
        open_and_close_a_window_with_a_comma_in_its_title(instance, &mut events).await;

        let marker = "hyproxide, done";
        dispatch::dispatch(instance, dispatch::event(marker))
            .await
            .unwrap();
        let custom = Event::Custom(marker.to_owned());
        let received = read_until(&mut events, "the custom event", |received| {
            received.contains(&custom)
        })
        .await;
        assert_all_known(&received);
    })
    .await;
}

async fn open_and_close_a_special_workspace(
    instance: &Instance,
    events: &mut Events,
    monitor: &str,
) {
    let special = unrenamed(WorkspaceAddress::Special("hyproxide".into()));
    let opened = Event::SpecialWorkspaceChanged {
        workspace: special.clone(),
        monitor: monitor.to_owned(),
    };
    let created = Event::WorkspaceCreated(special.clone());
    dispatch::dispatch(instance, workspace::toggle_special(Some("hyproxide")))
        .await
        .unwrap();
    let received = read_until(events, "special:hyproxide to open", |received| {
        received.contains(&opened) && received.contains(&created)
    })
    .await;
    assert_all_known(&received);

    let closed = Event::SpecialWorkspaceChanged {
        workspace: unrenamed(WorkspaceAddress::None),
        monitor: monitor.to_owned(),
    };
    let destroyed = Event::WorkspaceDestroyed(special);
    dispatch::dispatch(instance, workspace::toggle_special(Some("hyproxide")))
        .await
        .unwrap();
    let received = read_until(events, "special:hyproxide to close", |received| {
        received.contains(&closed) && received.contains(&destroyed)
    })
    .await;
    assert_all_known(&received);
}

async fn change_the_workspace(instance: &Instance, events: &mut Events) {
    let six = WorkspaceId::try_from(6).unwrap();
    let changed = [
        Event::WorkspaceChangedV1(WorkspaceAddress::Numbered(six)),
        Event::WorkspaceChanged(unrenamed(WorkspaceAddress::Numbered(six))),
    ];
    let focus_six = Focus::Workspace {
        workspace: six.into(),
        on_current_monitor: false,
    };
    dispatch::dispatch(instance, focus_six).await.unwrap();
    let received = read_until(events, "workspace 6", |received| {
        changed.iter().all(|event| received.contains(event))
    })
    .await;
    assert_all_known(&received);
}

async fn add_and_remove_an_output(instance: &Instance, events: &mut Events) {
    let output = "HYPROXIDE-1";
    let added = Event::MonitorAddedV1(output.to_owned());
    let create = Command::CreateOutput {
        backend: OutputBackend::Headless,
        name: Some(Word::try_from(output).unwrap()),
    };
    command::run(instance, &create).await.unwrap();
    let received = read_until(events, "the output to be added", |received| {
        received.contains(&added)
            && received
                .iter()
                .any(|event| matches!(event, Event::MonitorAdded { name, .. } if name == output))
    })
    .await;
    assert_all_known(&received);

    let removed = Event::MonitorRemovedV1(output.to_owned());
    let remove = Command::RemoveOutput(Word::try_from(output).unwrap());
    command::run(instance, &remove).await.unwrap();
    let received = read_until(events, "the output to be removed", |received| {
        received.contains(&removed)
            && received
                .iter()
                .any(|event| matches!(event, Event::MonitorRemoved { name, .. } if name == output))
    })
    .await;
    assert_all_known(&received);
}

/// The window keeps its address in the `openwindow` line, whose other fields
/// cannot be told apart. `activewindow`, whose class and title cannot be told
/// apart either, arrives as unknown, and `activewindowv2` carries the
/// address.
async fn open_and_close_a_window_with_a_comma_in_its_title(
    instance: &Instance,
    events: &mut Events,
) {
    let title = "hyproxide, live";
    let workspace = query::active_workspace(instance).await.unwrap().workspace;
    // foot gives its windows the class foot.
    let fields = format!("{},foot,{title}", workspace.address);
    let opened = |event: &Event| match event {
        Event::WindowOpenedUndivided {
            window,
            fields: read,
        } if *read == fields => Some(*window),
        _ => None,
    };
    let foot = format!("foot --title '{title}' --hold true");
    dispatch::dispatch(instance, dispatch::exec_cmd(&foot))
        .await
        .unwrap();
    // The window that opened, once focus went to it after it opened.
    let focused_after_opening = |received: &[Event]| {
        let (at, window) = received
            .iter()
            .enumerate()
            .find_map(|(at, event)| Some((at, opened(event)?)))?;
        let focused = Event::ActiveWindowChanged(Some(window));
        received[at..].contains(&focused).then_some(window)
    };
    let received = read_until(events, "the window to open and get focus", |received| {
        focused_after_opening(received).is_some()
    })
    .await;
    let window = focused_after_opening(&received).unwrap();
    for event in &received {
        if let Event::Unknown { name, .. } = event {
            assert_eq!(name, b"activewindow", "{event:?}");
        }
    }

    let close = window::close().window(WindowSelector::Address(window));
    dispatch::dispatch(instance, close).await.unwrap();
    let received = read_until(events, "the window to close", |received| {
        received.contains(&Event::WindowClosed(window))
    })
    .await;
    assert_all_known(&received);
}

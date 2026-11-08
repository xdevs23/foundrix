//! Events from a fake Hyprland: a listener on the event socket in a
//! directory made for each test, which writes lines in pieces.

mod support;

use hyproxide::event::{self, DATA_LIMIT, Event, Events};
use hyproxide::workspace::{WorkspaceAddress, WorkspaceId, WorkspaceRef};
use hyproxide::{Error, Instance};
use tokio::io::AsyncWriteExt as _;
use tokio::net::{UnixListener, UnixStream};

use support::TempDirectory;

/// Subscribe to a fake Hyprland, and return the events with the connection
/// Hyprland writes them into.
async fn subscribe() -> (TempDirectory, Events, UnixStream) {
    let directory = TempDirectory::new();
    let listener = UnixListener::bind(directory.path().join(".socket2.sock")).unwrap();
    let instance = Instance::at(directory.path());
    let (events, accepted) = tokio::join!(event::subscribe(&instance), listener.accept());
    (directory, events.unwrap(), accepted.unwrap().0)
}

const RECORDED: &[u8] = include_bytes!("../testdata/hyprland-events/socket2-events-0.57.1.log");

fn workspace_six() -> WorkspaceAddress {
    WorkspaceAddress::Numbered(WorkspaceId::try_from(6).unwrap())
}

/// Poll the next event until it read what Hyprland wrote so far, and drop it
/// while it waits for more. A byte sent through another socket after that
/// becomes readable in the same turn of the runtime as the bytes before it,
/// and the next event is polled first in that turn.
async fn read_what_arrived_and_drop(events: &mut Events) {
    let (mut sender, receiver) = UnixStream::pair().unwrap();
    sender.write_all(b"!").await.unwrap();
    tokio::select! {
        biased;
        event = events.next() => panic!("no event was complete, but {event:?} arrived"),
        readable = receiver.readable() => readable.unwrap(),
    }
}

#[tokio::test]
async fn lines_split_across_reads_arrive_whole() {
    let (_directory, mut events, mut hyprland) = subscribe().await;
    // Each piece ends inside a line, and its complete lines arrive before
    // the next piece is written, so the rest of that line comes in a later
    // read: after the event name, inside `>>`, and inside a character.
    let pieces: [(&[u8], Vec<Event>); 4] = [
        (
            b"workspace>>6\nworkspacev2>>6",
            vec![Event::WorkspaceChangedV1(workspace_six())],
        ),
        (
            b",6\nconfigreloaded>",
            vec![Event::WorkspaceChanged(WorkspaceRef {
                address: workspace_six(),
                name: "6".into(),
            })],
        ),
        (b">\ncustom>>caf\xc3", vec![Event::ConfigReloaded]),
        (
            b"\xa9, ok\nsubmap>>resize\nsubmap>>\n",
            vec![
                Event::Custom("café, ok".into()),
                Event::SubmapChanged(Some("resize".into())),
                Event::SubmapChanged(None),
            ],
        ),
    ];
    for (piece, expected) in pieces {
        hyprland.write_all(piece).await.unwrap();
        for event in expected {
            assert_eq!(events.next().await.unwrap(), event);
        }
    }
}

#[tokio::test]
async fn a_dropped_call_keeps_the_part_of_a_line_it_read() {
    let (_directory, mut events, mut hyprland) = subscribe().await;
    hyprland.write_all(b"workspace>>").await.unwrap();
    read_what_arrived_and_drop(&mut events).await;
    hyprland.write_all(b"6\n").await.unwrap();
    assert_eq!(
        events.next().await.unwrap(),
        Event::WorkspaceChangedV1(workspace_six())
    );
}

#[tokio::test]
async fn a_line_written_byte_by_byte_arrives_once_and_whole() {
    let (_directory, mut events, mut hyprland) = subscribe().await;
    let line = "custom>>café, ok\n".as_bytes();
    let (last, before) = line.split_last().unwrap();
    for byte in before {
        hyprland.write_all(&[*byte]).await.unwrap();
        read_what_arrived_and_drop(&mut events).await;
    }
    hyprland.write_all(&[*last]).await.unwrap();
    hyprland.write_all(b"workspace>>6\n").await.unwrap();
    assert_eq!(
        events.next().await.unwrap(),
        Event::Custom("café, ok".into())
    );
    assert_eq!(
        events.next().await.unwrap(),
        Event::WorkspaceChangedV1(workspace_six())
    );
}

#[tokio::test]
async fn the_recorded_log_in_one_write_reads_as_line_by_line() {
    let (_directory, mut events, mut hyprland) = subscribe().await;
    let mut line_by_line = Vec::new();
    for line in RECORDED.split_inclusive(|&byte| byte == b'\n') {
        hyprland.write_all(line).await.unwrap();
        line_by_line.push(events.next().await.unwrap());
    }
    hyprland.write_all(RECORDED).await.unwrap();
    for expected in line_by_line {
        assert_eq!(events.next().await.unwrap(), expected);
    }
}

#[tokio::test]
async fn a_line_hyprland_cut_inside_a_character_does_not_end_the_stream() {
    let (_directory, mut events, mut hyprland) = subscribe().await;
    // "ff," and 340 characters of 3 bytes end 1 byte before the limit.
    let data = format!("ff,{}", "€".repeat(400));
    let cut = &data.as_bytes()[..DATA_LIMIT];
    let lines = [b"windowtitlev2>>", cut, b"\nworkspace>>6\n"].concat();
    hyprland.write_all(&lines).await.unwrap();
    assert_eq!(
        events.next().await.unwrap(),
        Event::Unknown {
            name: b"windowtitlev2".to_vec(),
            data: cut.to_vec(),
        }
    );
    assert_eq!(
        events.next().await.unwrap(),
        Event::WorkspaceChangedV1(workspace_six())
    );
}

#[tokio::test]
async fn an_unknown_line_does_not_end_the_stream() {
    let (_directory, mut events, mut hyprland) = subscribe().await;
    hyprland
        .write_all(b"windowfocused>>ff\nworkspace>>6\n")
        .await
        .unwrap();
    assert_eq!(
        events.next().await.unwrap(),
        Event::Unknown {
            name: b"windowfocused".to_vec(),
            data: b"ff".to_vec(),
        }
    );
    assert_eq!(
        events.next().await.unwrap(),
        Event::WorkspaceChangedV1(workspace_six())
    );
}

#[tokio::test]
async fn the_stream_ends_when_hyprland_closes_the_socket() {
    let (directory, mut events, mut hyprland) = subscribe().await;
    // A line cut off by the close: `workspace>>1` would be another
    // workspace.
    hyprland
        .write_all(b"workspace>>6\nworkspace>>1")
        .await
        .unwrap();
    drop(hyprland);
    assert_eq!(
        events.next().await.unwrap(),
        Event::WorkspaceChangedV1(workspace_six())
    );
    for _ in 0..2 {
        let ended = events.next().await;
        assert!(
            matches!(&ended, Err(Error::EventsClosed { path }) if *path == directory.path().join(".socket2.sock")),
            "{ended:?}"
        );
    }
}

#[tokio::test]
async fn subscribing_without_a_socket_fails_to_connect() {
    let directory = TempDirectory::new();
    let subscribed = event::subscribe(&Instance::at(directory.path())).await;
    assert!(
        matches!(&subscribed, Err(Error::Connect { path, .. }) if *path == directory.path().join(".socket2.sock")),
        "{subscribed:?}"
    );
}

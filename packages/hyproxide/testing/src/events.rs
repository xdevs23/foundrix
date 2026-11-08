use hyproxide::event::{Event, Events};

/// Read events until `done` holds for the events read so far, and return
/// them. Prints what it waits for and every event that arrives, so the log
/// of a test that hangs shows which event is missing.
///
/// # Panics
///
/// When the event stream ends.
pub async fn read_until(
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

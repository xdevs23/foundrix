//! How Hyprland writes an event: `<name>>><data>`, where the data is the
//! fields of the event joined with commas
//! (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/ipc/s2/S2.cpp>,
//! checked 2026-11-08).

use std::str::{self, FromStr};

use super::{Event, ScreencastSource, ScreencastTarget};
use crate::address::Address;
use crate::monitor::MonitorId;
use crate::workspace::{WorkspaceAddress, WorkspaceId, WorkspaceRef};
use Field::{Text, Token};

/// The most bytes of data Hyprland writes in a line: it cuts the data of
/// every event after them, also inside a character
/// (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/ipc/s2/S2.cpp>,
/// `formatEvent`, checked 2026-11-08). A text at the end of a line with this
/// much data may be cut.
pub const DATA_LIMIT: usize = 1024;

/// Read one line, without its newline, into an event.
pub(super) fn read(line: &[u8]) -> Event {
    let separator = line.windows(2).position(|pair| pair == b">>");
    let (name, data) = separator.map_or((line, None), |at| (&line[..at], Some(&line[at + 2..])));
    data.and_then(|data| read_known(name, data))
        .unwrap_or_else(|| Event::Unknown {
            name: name.to_vec(),
            data: data.unwrap_or_default().to_vec(),
        })
}

fn read_known(name: &[u8], data: &[u8]) -> Option<Event> {
    let (_, read) = READERS.iter().find(|(known, _)| known.as_bytes() == name)?;
    read(str::from_utf8(data).ok()?)
}

/// Reads the data of one event, `None` when it does not read exactly.
type Reader = fn(&str) -> Option<Event>;

/// The reader of each event of Hyprland 0.57.1, by the name of the event.
const READERS: &[(&str, Reader)] = &[
    ("openwindow", |data| {
        let [window, fields] = split(data, [Token, Text])?;
        let window = address(window)?;
        let Some([workspace, class, title]) = split(fields, [Text, Text, Text]) else {
            let fields = fields.to_owned();
            return Some(Event::WindowOpenedUndivided { window, fields });
        };
        Some(Event::WindowOpened {
            window,
            workspace: WorkspaceAddress::read(workspace)?,
            class: class.to_owned(),
            title: title.to_owned(),
        })
    }),
    ("closewindow", |data| address(data).map(Event::WindowClosed)),
    ("movewindow", |data| {
        let [window, workspace] = split(data, [Token, Text])?;
        Some(Event::WindowMovedV1 {
            window: address(window)?,
            workspace: WorkspaceAddress::read(workspace)?,
        })
    }),
    ("movewindowv2", |data| {
        let [window, workspace, shown] = split(data, [Token, Text, Text])?;
        Some(Event::WindowMoved {
            window: address(window)?,
            workspace: workspace_shown_as(workspace, shown)?,
        })
    }),
    ("windowtitle", |data| {
        address(data).map(Event::WindowTitleChangedV1)
    }),
    ("windowtitlev2", |data| {
        let [window, title] = split(data, [Token, Text])?;
        Some(Event::WindowTitleChanged {
            window: address(window)?,
            title: title.to_owned(),
        })
    }),
    ("activewindow", |data| {
        let [class, title] = split(data, [Text, Text])?;
        Some(Event::ActiveWindowChangedV1 {
            class: class.to_owned(),
            title: title.to_owned(),
        })
    }),
    ("activewindowv2", |data| {
        about_window_or_none(data, Event::ActiveWindowChanged)
    }),
    ("urgent", |data| address(data).map(Event::WindowUrgent)),
    ("fullscreen", |data| {
        flag(data).map(Event::FullscreenChanged)
    }),
    ("changefloatingmode", |data| {
        let [window, floating] = split(data, [Token, Token])?;
        Some(Event::FloatingChanged {
            window: address(window)?,
            floating: flag(floating)?,
        })
    }),
    ("pin", |data| {
        let [window, pinned] = split(data, [Token, Token])?;
        Some(Event::PinnedChanged {
            window: address(window)?,
            pinned: flag(pinned)?,
        })
    }),
    ("minimized", |data| {
        let [window, minimized] = split(data, [Token, Token])?;
        Some(Event::MinimizedChanged {
            window: address(window)?,
            minimized: flag(minimized)?,
        })
    }),
    ("bell", |data| about_window_or_none(data, Event::Bell)),
    ("kill", |data| address(data).map(Event::WindowKilled)),
    ("togglegroup", |data| {
        let [formed, window] = split(data, [Token, Token])?;
        Some(Event::GroupToggled {
            window: address(window)?,
            formed: flag(formed)?,
        })
    }),
    ("moveintogroup", |data| {
        address(data).map(Event::WindowMovedIntoGroup)
    }),
    ("moveoutofgroup", |data| {
        address(data).map(Event::WindowMovedOutOfGroup)
    }),
    ("lockgroups", |data| {
        flag(data).map(Event::GroupsLockChanged)
    }),
    ("workspace", |data| {
        WorkspaceAddress::read(data).map(Event::WorkspaceChangedV1)
    }),
    ("workspacev2", |data| {
        workspace(data).map(Event::WorkspaceChanged)
    }),
    ("createworkspace", |data| {
        WorkspaceAddress::read(data).map(Event::WorkspaceCreatedV1)
    }),
    ("createworkspacev2", |data| {
        workspace(data).map(Event::WorkspaceCreated)
    }),
    ("destroyworkspace", |data| {
        WorkspaceAddress::read(data).map(Event::WorkspaceDestroyedV1)
    }),
    ("destroyworkspacev2", |data| {
        workspace(data).map(Event::WorkspaceDestroyed)
    }),
    ("renameworkspace", |data| {
        workspace(data).map(Event::WorkspaceRenamed)
    }),
    ("changeworkspaceid", |data| {
        let [previous, current] = split(data, [Token, Token])?;
        Some(Event::WorkspaceIdChanged {
            previous: workspace_id(previous)?,
            current: workspace_id(current)?,
        })
    }),
    ("moveworkspace", |data| {
        let [workspace, monitor] = split(data, [Text, Text])?;
        Some(Event::WorkspaceMovedV1 {
            workspace: WorkspaceAddress::read(workspace)?,
            monitor: monitor.to_owned(),
        })
    }),
    ("moveworkspacev2", |data| {
        let [workspace, shown, monitor] = split(data, [Text, Text, Text])?;
        Some(Event::WorkspaceMoved {
            workspace: workspace_shown_as(workspace, shown)?,
            monitor: monitor.to_owned(),
        })
    }),
    ("activespecial", |data| {
        let [workspace, monitor] = split(data, [Text, Text])?;
        Some(Event::SpecialWorkspaceChangedV1 {
            workspace: WorkspaceAddress::read(workspace)?,
            monitor: monitor.to_owned(),
        })
    }),
    ("activespecialv2", |data| {
        let [workspace, shown, monitor] = split(data, [Text, Text, Text])?;
        Some(Event::SpecialWorkspaceChanged {
            workspace: workspace_shown_as(workspace, shown)?,
            monitor: monitor.to_owned(),
        })
    }),
    ("focusedmon", |data| {
        let [monitor, workspace] = split(data, [Text, Text])?;
        // `?` stands for no workspace and for the workspace named `?`.
        let workspace = Some(workspace).filter(|workspace| *workspace != "?")?;
        Some(Event::MonitorFocusedV1 {
            monitor: monitor.to_owned(),
            workspace: WorkspaceAddress::read(workspace)?,
        })
    }),
    ("focusedmonv2", |data| {
        let [monitor, workspace] = split(data, [Text, Text])?;
        Some(Event::MonitorFocused {
            monitor: monitor.to_owned(),
            workspace: WorkspaceAddress::read(workspace)?,
        })
    }),
    ("monitoradded", |data| {
        Some(Event::MonitorAddedV1(data.to_owned()))
    }),
    ("monitoraddedv2", |data| {
        let [id, name, description] = split(data, [Token, Text, Token])?;
        Some(Event::MonitorAdded {
            id: MonitorId::new(decimal(id)?),
            name: name.to_owned(),
            description: description.to_owned(),
        })
    }),
    ("monitorremoved", |data| {
        Some(Event::MonitorRemovedV1(data.to_owned()))
    }),
    ("monitorremovedv2", |data| {
        let [id, name, description] = split(data, [Token, Text, Token])?;
        Some(Event::MonitorRemoved {
            id: MonitorId::new(decimal(id)?),
            name: name.to_owned(),
            description: description.to_owned(),
        })
    }),
    ("openlayer", |data| {
        Some(Event::LayerOpened(data.to_owned()))
    }),
    ("closelayer", |data| {
        Some(Event::LayerClosed(data.to_owned()))
    }),
    ("activelayout", |data| {
        let [keyboard, layout] = split(data, [Token, Text])?;
        Some(Event::KeyboardLayoutChanged {
            keyboard: keyboard.to_owned(),
            layout: layout.to_owned(),
        })
    }),
    ("submap", |data| {
        let submap = Some(data).filter(|submap| !submap.is_empty());
        Some(Event::SubmapChanged(submap.map(str::to_owned)))
    }),
    ("screencast", |data| {
        let [active, source] = split(data, [Token, Token])?;
        Some(Event::ScreencastChangedV1 {
            active: flag(active)?,
            source: screencast_source(source)?,
        })
    }),
    ("screencastv2", |data| {
        let [active, source, name] = split(data, [Token, Token, Text])?;
        Some(Event::ScreencastChanged {
            active: flag(active)?,
            target: screencast_target(screencast_source(source)?, name)?,
        })
    }),
    ("configreloaded", |data| {
        data.is_empty().then_some(Event::ConfigReloaded)
    }),
    ("custom", |data| Some(Event::Custom(data.to_owned()))),
];

/// Whether Hyprland can write a comma into a field of an event.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Field {
    /// A field without commas, such as an address, a number or a name
    /// Hyprland removed the commas from.
    Token,
    /// Text that can hold commas, such as a title or a workspace name.
    Text,
}

/// Split the data of an event into its fields. The tokens before the first
/// text are read from the start, the tokens after the last text from the
/// end. What lies between is one text with all its commas, or several fields
/// that need exactly as many commas as separate them. Data of tokens alone
/// needs exactly their separators. `None` when the data has fewer fields, or
/// more commas than its fields allow.
fn split<const N: usize>(data: &str, layout: [Field; N]) -> Option<[&str; N]> {
    const { assert!(N > 0, "an event with data has a field") };
    let mut fields = [""; N];
    let first_text = layout.iter().position(|field| *field == Text);
    let last_text = layout.iter().rposition(|field| *field == Text);
    let (Some(first), Some(last)) = (first_text, last_text) else {
        return fill_exactly(&mut fields, data).then_some(fields);
    };

    let mut rest = data;
    for field in &mut fields[..first] {
        (*field, rest) = rest.split_once(',')?;
    }
    for field in fields[last + 1..].iter_mut().rev() {
        (rest, *field) = rest.rsplit_once(',')?;
    }
    if first == last {
        fields[first] = rest;
        return Some(fields);
    }
    fill_exactly(&mut fields[first..=last], rest).then_some(fields)
}

/// Fill `fields` with the pieces of `text` between its commas, and tell
/// whether it has exactly as many pieces.
fn fill_exactly<'text>(fields: &mut [&'text str], text: &'text str) -> bool {
    let mut pieces = text.split(',');
    for field in fields {
        let Some(piece) = pieces.next() else {
            return false;
        };
        *field = piece;
    }
    pieces.next().is_none()
}

/// A window address, written as hex without `0x`.
fn address(text: &str) -> Option<Address> {
    Address::from_hex(text).ok().flatten()
}

/// An event about the window at an address, or about none for empty data.
fn about_window_or_none(data: &str, event: fn(Option<Address>) -> Event) -> Option<Event> {
    if data.is_empty() {
        return Some(event(None));
    }
    address(data).map(|window| event(Some(window)))
}

/// `1` or `0`.
fn flag(text: &str) -> Option<bool> {
    match text {
        "1" => Some(true),
        "0" => Some(false),
        _ => None,
    }
}

/// A number in decimal digits, after a `-` when negative.
fn decimal<T: FromStr>(text: &str) -> Option<T> {
    let digits = text.strip_prefix('-').unwrap_or(text);
    let decimal = !digits.is_empty() && digits.bytes().all(|byte| byte.is_ascii_digit());
    decimal.then(|| text.parse().ok()).flatten()
}

fn workspace_id(text: &str) -> Option<WorkspaceId> {
    WorkspaceId::try_from(decimal::<u32>(text)?).ok()
}

/// A workspace written as its address and the name shown for it.
fn workspace(data: &str) -> Option<WorkspaceRef> {
    let [workspace, shown] = split(data, [Text, Text])?;
    workspace_shown_as(workspace, shown)
}

fn workspace_shown_as(address: &str, shown: &str) -> Option<WorkspaceRef> {
    Some(WorkspaceRef {
        address: WorkspaceAddress::read(address)?,
        name: shown.to_owned(),
    })
}

fn screencast_source(text: &str) -> Option<ScreencastSource> {
    match text {
        "monitor" => Some(ScreencastSource::Monitor),
        "window" => Some(ScreencastSource::Window),
        "region" => Some(ScreencastSource::Region),
        "workspace" => Some(ScreencastSource::Workspace),
        _ => None,
    }
}

/// What a screencast from `source` shows, by the name Hyprland writes for it.
fn screencast_target(source: ScreencastSource, name: &str) -> Option<ScreencastTarget> {
    Some(match source {
        ScreencastSource::Monitor => ScreencastTarget::Monitor(name.to_owned()),
        ScreencastSource::Region => ScreencastTarget::Region(name.to_owned()),
        ScreencastSource::Window => ScreencastTarget::Window {
            title: name.to_owned(),
        },
        ScreencastSource::Workspace => ScreencastTarget::Workspace(WorkspaceAddress::read(name)?),
    })
}

#[cfg(test)]
mod tests {
    use super::Field::{Text, Token};
    use super::*;

    #[test]
    fn a_single_text_takes_every_comma_between_the_tokens() {
        assert_eq!(
            split("1,HEADLESS,3,", [Token, Text, Token]),
            Some(["1", "HEADLESS,3", ""])
        );
        assert_eq!(
            split("abc,a, b, c", [Token, Text]),
            Some(["abc", "a, b, c"])
        );
        assert_eq!(split("a,b", [Text]), Some(["a,b"]));
    }

    #[test]
    fn several_texts_need_exactly_their_separators() {
        assert_eq!(
            split(",,HEADLESS-2", [Text, Text, Text]),
            Some(["", "", "HEADLESS-2"])
        );
        assert_eq!(split("a,b,c", [Text, Text]), None);
        assert_eq!(split("ff,1,foot,a, b", [Token, Text, Text, Text]), None);
    }

    #[test]
    fn tokens_hold_no_comma() {
        assert_eq!(split("1,0", [Token, Token]), Some(["1", "0"]));
        assert_eq!(split("1,0,1", [Token, Token]), None);
        assert_eq!(split("1", [Token, Token]), None);
        assert_eq!(split("1,2", [Token]), None);
        assert_eq!(split("", [Token]), Some([""]));
    }

    #[test]
    fn numbers_are_bare_decimal_digits() {
        assert_eq!(decimal::<i64>("2"), Some(2));
        assert_eq!(decimal::<i64>("-1"), Some(-1));
        for text in ["", "-", "+2", " 2", "2a", "0x2"] {
            assert_eq!(decimal::<i64>(text), None, "{text:?}");
        }
        assert_eq!(decimal::<u32>("-1"), None);
    }
}

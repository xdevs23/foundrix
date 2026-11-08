//! `testdata/hyprland-events/socket2-events-0.57.1.log` was recorded from a
//! headless Hyprland 0.57.1 with the output Virtual-1, while the special
//! workspace `special:scratch` was opened and closed, workspaces changed
//! and the outputs HEADLESS-2 and HEADLESS-3 were added and removed.

use std::num::NonZeroU64;

use super::line::read;
use super::*;
use crate::workspace::WorkspaceName;

const RECORDED: &str = include_str!("../../testdata/hyprland-events/socket2-events-0.57.1.log");

fn event(line: &str) -> Event {
    read(line.as_bytes())
}

fn unknown(name: &str, data: &[u8]) -> Event {
    Event::Unknown {
        name: name.as_bytes().to_vec(),
        data: data.to_vec(),
    }
}

fn window(address: u64) -> Address {
    Address::new(NonZeroU64::new(address).unwrap())
}

fn id(number: u32) -> WorkspaceId {
    WorkspaceId::try_from(number).unwrap()
}

fn numbered(number: u32) -> WorkspaceAddress {
    WorkspaceAddress::Numbered(id(number))
}

fn named(name: &str) -> WorkspaceAddress {
    WorkspaceAddress::Named(WorkspaceName::try_from(name).unwrap())
}

fn scratch() -> WorkspaceAddress {
    WorkspaceAddress::Special("scratch".into())
}

fn no_workspace() -> WorkspaceAddress {
    WorkspaceAddress::None
}

fn shown_as(address: WorkspaceAddress, name: &str) -> WorkspaceRef {
    WorkspaceRef {
        address,
        name: name.to_owned(),
    }
}

/// A workspace whose shown name is its address, as long as nobody renamed
/// it.
fn unrenamed(address: WorkspaceAddress) -> WorkspaceRef {
    let name = address.to_string();
    shown_as(address, &name)
}

fn assert_reads(cases: impl IntoIterator<Item = (&'static str, Event)>) {
    for (line, expected) in cases {
        assert_eq!(event(line), expected, "{line}");
    }
}

/// The line Hyprland writes for an event of the recorded log, so a test can
/// compare every field read from a line with the line.
fn wire(event: &Event) -> String {
    let unrenamed = |workspace: &WorkspaceRef| {
        assert_eq!(workspace.name, workspace.address.to_string(), "{event:?}");
        format!("{0},{0}", workspace.address)
    };
    match event {
        Event::WorkspaceCreatedV1(workspace) => format!("createworkspace>>{workspace}"),
        Event::WorkspaceCreated(workspace) => {
            format!("createworkspacev2>>{}", unrenamed(workspace))
        }
        Event::WorkspaceDestroyedV1(workspace) => format!("destroyworkspace>>{workspace}"),
        Event::WorkspaceDestroyed(workspace) => {
            format!("destroyworkspacev2>>{}", unrenamed(workspace))
        }
        Event::WorkspaceChangedV1(workspace) => format!("workspace>>{workspace}"),
        Event::WorkspaceChanged(workspace) => format!("workspacev2>>{}", unrenamed(workspace)),
        Event::SpecialWorkspaceChangedV1 { workspace, monitor } => {
            format!("activespecial>>{workspace},{monitor}")
        }
        Event::SpecialWorkspaceChanged { workspace, monitor } => {
            format!("activespecialv2>>{},{monitor}", unrenamed(workspace))
        }
        Event::WorkspaceMovedV1 { workspace, monitor } => {
            format!("moveworkspace>>{workspace},{monitor}")
        }
        Event::WorkspaceMoved { workspace, monitor } => {
            format!("moveworkspacev2>>{},{monitor}", unrenamed(workspace))
        }
        Event::MonitorFocusedV1 { monitor, workspace } => {
            format!("focusedmon>>{monitor},{workspace}")
        }
        Event::MonitorFocused { monitor, workspace } => {
            format!("focusedmonv2>>{monitor},{workspace}")
        }
        Event::MonitorAddedV1(name) => format!("monitoradded>>{name}"),
        Event::MonitorAdded {
            id,
            name,
            description,
        } => format!("monitoraddedv2>>{id},{name},{description}"),
        Event::MonitorRemovedV1(name) => format!("monitorremoved>>{name}"),
        Event::MonitorRemoved {
            id,
            name,
            description,
        } => format!("monitorremovedv2>>{id},{name},{description}"),
        other => panic!("the recorded log has no {other:?}"),
    }
}

#[test]
fn every_recorded_line_reads_into_the_fields_it_was_written_from() {
    for line in RECORDED.lines() {
        let read = event(line);
        assert!(!matches!(read, Event::Unknown { .. }), "{line}: {read:?}");
        assert_eq!(wire(&read), line, "{read:?}");
    }
}

/// Assert that each line is in the recorded log and reads into its event.
fn assert_recorded_reads<const N: usize>(cases: [(&'static str, Event); N]) {
    for (line, _) in &cases {
        assert!(RECORDED.lines().any(|recorded| recorded == *line), "{line}");
    }
    assert_reads(cases);
}

#[test]
fn recorded_special_workspace_events_read_into_their_fields() {
    assert_recorded_reads([
        (
            "createworkspace>>special:scratch",
            Event::WorkspaceCreatedV1(scratch()),
        ),
        (
            "createworkspacev2>>special:scratch,special:scratch",
            Event::WorkspaceCreated(unrenamed(scratch())),
        ),
        (
            "activespecial>>special:scratch,HEADLESS-2",
            Event::SpecialWorkspaceChangedV1 {
                workspace: scratch(),
                monitor: "HEADLESS-2".into(),
            },
        ),
        (
            "activespecialv2>>special:scratch,special:scratch,HEADLESS-2",
            Event::SpecialWorkspaceChanged {
                workspace: unrenamed(scratch()),
                monitor: "HEADLESS-2".into(),
            },
        ),
        (
            "activespecial>>,HEADLESS-2",
            Event::SpecialWorkspaceChangedV1 {
                workspace: no_workspace(),
                monitor: "HEADLESS-2".into(),
            },
        ),
        (
            "activespecialv2>>,,HEADLESS-2",
            Event::SpecialWorkspaceChanged {
                workspace: unrenamed(no_workspace()),
                monitor: "HEADLESS-2".into(),
            },
        ),
        (
            "destroyworkspace>>special:scratch",
            Event::WorkspaceDestroyedV1(scratch()),
        ),
        (
            "destroyworkspacev2>>special:scratch,special:scratch",
            Event::WorkspaceDestroyed(unrenamed(scratch())),
        ),
    ]);
}

#[test]
fn recorded_workspace_and_monitor_events_read_into_their_fields() {
    assert_recorded_reads([
        ("workspace>>6", Event::WorkspaceChangedV1(numbered(6))),
        (
            "workspacev2>>6,6",
            Event::WorkspaceChanged(unrenamed(numbered(6))),
        ),
        (
            "monitoradded>>HEADLESS-3",
            Event::MonitorAddedV1("HEADLESS-3".into()),
        ),
        (
            "monitoraddedv2>>2,HEADLESS-3,",
            Event::MonitorAdded {
                id: MonitorId::new(2),
                name: "HEADLESS-3".into(),
                description: String::new(),
            },
        ),
        (
            "moveworkspace>>1,Virtual-1",
            Event::WorkspaceMovedV1 {
                workspace: numbered(1),
                monitor: "Virtual-1".into(),
            },
        ),
        (
            "moveworkspacev2>>1,1,Virtual-1",
            Event::WorkspaceMoved {
                workspace: unrenamed(numbered(1)),
                monitor: "Virtual-1".into(),
            },
        ),
        (
            "focusedmon>>Virtual-1,10",
            Event::MonitorFocusedV1 {
                monitor: "Virtual-1".into(),
                workspace: numbered(10),
            },
        ),
        (
            "focusedmonv2>>Virtual-1,10",
            Event::MonitorFocused {
                monitor: "Virtual-1".into(),
                workspace: numbered(10),
            },
        ),
        (
            "monitorremoved>>HEADLESS-3",
            Event::MonitorRemovedV1("HEADLESS-3".into()),
        ),
        (
            "monitorremovedv2>>2,HEADLESS-3,",
            Event::MonitorRemoved {
                id: MonitorId::new(2),
                name: "HEADLESS-3".into(),
                description: String::new(),
            },
        ),
    ]);
}

#[test]
fn window_events_read_into_their_fields() {
    let firefox = window(0x5731_06b0_db30);
    assert_reads([
        (
            "openwindow>>573106b0db30,1,firefox,Hyprland",
            Event::WindowOpened {
                window: firefox,
                workspace: numbered(1),
                class: "firefox".into(),
                title: "Hyprland".into(),
            },
        ),
        ("closewindow>>573106b0db30", Event::WindowClosed(firefox)),
        (
            "movewindow>>573106b0db30,web",
            Event::WindowMovedV1 {
                window: firefox,
                workspace: named("web"),
            },
        ),
        (
            "movewindowv2>>573106b0db30,web,Web",
            Event::WindowMoved {
                window: firefox,
                workspace: shown_as(named("web"), "Web"),
            },
        ),
        (
            "windowtitle>>573106b0db30",
            Event::WindowTitleChangedV1(firefox),
        ),
        (
            "activewindow>>firefox,Hyprland",
            Event::ActiveWindowChangedV1 {
                class: "firefox".into(),
                title: "Hyprland".into(),
            },
        ),
        (
            "activewindow>>,",
            Event::ActiveWindowChangedV1 {
                class: String::new(),
                title: String::new(),
            },
        ),
        (
            "activewindowv2>>573106b0db30",
            Event::ActiveWindowChanged(Some(firefox)),
        ),
        ("activewindowv2>>", Event::ActiveWindowChanged(None)),
        ("urgent>>573106b0db30", Event::WindowUrgent(firefox)),
        ("fullscreen>>1", Event::FullscreenChanged(true)),
        ("fullscreen>>0", Event::FullscreenChanged(false)),
        (
            "changefloatingmode>>573106b0db30,1",
            Event::FloatingChanged {
                window: firefox,
                floating: true,
            },
        ),
        (
            "pin>>573106b0db30,0",
            Event::PinnedChanged {
                window: firefox,
                pinned: false,
            },
        ),
        (
            "minimized>>573106b0db30,1",
            Event::MinimizedChanged {
                window: firefox,
                minimized: true,
            },
        ),
        ("bell>>573106b0db30", Event::Bell(Some(firefox))),
        ("bell>>", Event::Bell(None)),
        ("kill>>573106b0db30", Event::WindowKilled(firefox)),
        (
            "togglegroup>>1,573106b0db30",
            Event::GroupToggled {
                window: firefox,
                formed: true,
            },
        ),
        (
            "togglegroup>>0,573106b0db30",
            Event::GroupToggled {
                window: firefox,
                formed: false,
            },
        ),
        (
            "moveintogroup>>573106b0db30",
            Event::WindowMovedIntoGroup(firefox),
        ),
        (
            "moveoutofgroup>>573106b0db30",
            Event::WindowMovedOutOfGroup(firefox),
        ),
        ("lockgroups>>1", Event::GroupsLockChanged(true)),
    ]);
}

#[test]
fn other_events_read_into_their_fields() {
    assert_reads([
        (
            "renameworkspace>>3,code",
            Event::WorkspaceRenamed(shown_as(numbered(3), "code")),
        ),
        (
            "changeworkspaceid>>3,7",
            Event::WorkspaceIdChanged {
                previous: id(3),
                current: id(7),
            },
        ),
        (
            "focusedmonv2>>DP-1,",
            Event::MonitorFocused {
                monitor: "DP-1".into(),
                workspace: no_workspace(),
            },
        ),
        ("openlayer>>waybar", Event::LayerOpened("waybar".into())),
        ("closelayer>>waybar", Event::LayerClosed("waybar".into())),
        (
            "activelayout>>at-translated-set-2-keyboard,German",
            Event::KeyboardLayoutChanged {
                keyboard: "at-translated-set-2-keyboard".into(),
                layout: "German".into(),
            },
        ),
        (
            "submap>>resize",
            Event::SubmapChanged(Some("resize".into())),
        ),
        ("submap>>", Event::SubmapChanged(None)),
        (
            "screencast>>1,monitor",
            Event::ScreencastChangedV1 {
                active: true,
                source: ScreencastSource::Monitor,
            },
        ),
        (
            "screencastv2>>0,region,DP-1",
            Event::ScreencastChanged {
                active: false,
                target: ScreencastTarget::Region("DP-1".into()),
            },
        ),
        (
            "screencastv2>>1,monitor,DP-1",
            Event::ScreencastChanged {
                active: true,
                target: ScreencastTarget::Monitor("DP-1".into()),
            },
        ),
        (
            "screencastv2>>1,workspace,special:scratch",
            Event::ScreencastChanged {
                active: true,
                target: ScreencastTarget::Workspace(scratch()),
            },
        ),
        ("configreloaded>>", Event::ConfigReloaded),
        ("custom>>hello", Event::Custom("hello".into())),
    ]);
}

#[test]
fn a_text_with_tokens_around_it_keeps_its_commas() {
    let window = window(0xff);
    assert_reads([
        (
            "windowtitlev2>>ff,Inbox, 3 unread",
            Event::WindowTitleChanged {
                window,
                title: "Inbox, 3 unread".into(),
            },
        ),
        ("workspace>>a,b", Event::WorkspaceChangedV1(named("a,b"))),
        (
            "movewindow>>ff,special:a,b",
            Event::WindowMovedV1 {
                window,
                workspace: WorkspaceAddress::Special("a,b".into()),
            },
        ),
        (
            "monitoraddedv2>>3,MY,OUTPUT,Dell U2720Q 1234",
            Event::MonitorAdded {
                id: MonitorId::new(3),
                name: "MY,OUTPUT".into(),
                description: "Dell U2720Q 1234".into(),
            },
        ),
        (
            "activelayout>>keyboard,English (US, intl)",
            Event::KeyboardLayoutChanged {
                keyboard: "keyboard".into(),
                layout: "English (US, intl)".into(),
            },
        ),
        (
            "screencastv2>>1,window,a, b",
            Event::ScreencastChanged {
                active: true,
                target: ScreencastTarget::Window {
                    title: "a, b".into(),
                },
            },
        ),
        ("custom>>a,b>>c", Event::Custom("a,b>>c".into())),
        ("openlayer>>a,b", Event::LayerOpened("a,b".into())),
    ]);
}

#[test]
fn an_opened_window_with_more_commas_keeps_its_address() {
    for fields in ["1,foot,a, b", "1,org,foot,a", "my,web,foot,a"] {
        let line = format!("openwindow>>ff,{fields}");
        assert_eq!(
            event(&line),
            Event::WindowOpenedUndivided {
                window: window(0xff),
                fields: fields.into(),
            },
            "{line}"
        );
    }
}

#[test]
fn texts_next_to_each_other_with_a_comma_are_unknown() {
    for (name, data) in [
        ("activewindow", "foot,a, b"),
        ("workspacev2", "a,b,a,b"),
        ("moveworkspacev2", "1,1,MY,OUTPUT"),
        ("focusedmonv2", "MY,OUTPUT,1"),
    ] {
        let line = format!("{name}>>{data}");
        assert_eq!(event(&line), unknown(name, data.as_bytes()), "{line}");
    }
}

#[test]
fn lines_without_the_form_of_their_event_are_unknown() {
    for (name, data) in [
        ("closewindow", "window"),
        ("closewindow", "0"),
        ("closewindow", ""),
        ("closewindow", "+ff"),
        ("closewindow", "FF"),
        ("openwindow", "+ff,1,foot,a"),
        ("openwindow", "ff,0,foot,a"),
        ("screencastv2", "1,workspace,0"),
        ("fullscreen", "2"),
        ("changeworkspaceid", "+3,7"),
        ("changeworkspaceid", "3"),
        ("workspace", "0"),
        ("pin", "ff,1,1"),
        ("monitoraddedv2", "HEADLESS-3"),
        ("screencast", "1,ERR NONE"),
        ("focusedmon", "Virtual-1,?"),
        ("configreloaded", "now"),
        ("windowfocused", "ff"),
    ] {
        let line = format!("{name}>>{data}");
        assert_eq!(event(&line), unknown(name, data.as_bytes()), "{line}");
    }
}

/// The line Hyprland writes for `data`: its first [`DATA_LIMIT`] bytes.
fn cut_by_hyprland(name: &str, data: &[u8]) -> Vec<u8> {
    let kept = &data[..data.len().min(DATA_LIMIT)];
    [name.as_bytes(), b">>", kept].concat()
}

#[test]
fn the_longest_data_hyprland_writes_reads_whole() {
    let line = cut_by_hyprland(
        "windowtitlev2",
        format!("ff,{}", "a".repeat(2000)).as_bytes(),
    );
    assert_eq!(
        read(&line),
        Event::WindowTitleChanged {
            window: window(0xff),
            title: "a".repeat(DATA_LIMIT - "ff,".len()),
        }
    );
}

#[test]
fn a_line_cut_inside_a_character_is_unknown_with_its_bytes() {
    // "ff," and 340 characters of 3 bytes end 1 byte before the limit.
    let data = format!("ff,{}", "€".repeat(400));
    let line = cut_by_hyprland("windowtitlev2", data.as_bytes());
    assert_eq!(
        read(&line),
        unknown("windowtitlev2", &data.as_bytes()[..DATA_LIMIT])
    );
}

#[test]
fn lines_that_are_not_utf8_are_unknown_with_their_bytes() {
    let cut_inside_a_character = b"windowtitlev2>>ff,caf\xc3";
    assert_eq!(
        read(cut_inside_a_character),
        unknown("windowtitlev2", b"ff,caf\xc3")
    );
}

#[test]
fn a_line_without_separator_is_unknown_by_its_whole_text() {
    assert_eq!(event("configreloaded"), unknown("configreloaded", b""));
}

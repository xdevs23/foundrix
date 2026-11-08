//! The answers under `testdata/hyprland-answers` were recorded from a
//! headless Hyprland 0.57.1 with one output, Virtual-1, and one terminal
//! window titled "terminal". The file names show what else was set up:
//!
//! * `special`: the window sits on the special workspace `special:scratch`;
//! * `two-outputs`: a second output, HEADLESS-2, was created;
//! * `disabled`: HEADLESS-2 was disabled;
//! * `named`: Virtual-1 shows the named workspace `web`;
//! * `none`: there is no window, or no configuration error.

use super::*;
use crate::geometry::Size;
use crate::keyboard::Modifier;
use crate::monitor::MonitorId;
use crate::window::{FullscreenState, StableId};
use crate::workspace::{WorkspaceId, WorkspaceKind, WorkspaceRef};

macro_rules! recorded {
    ($file:literal) => {
        include_str!(concat!("../../testdata/hyprland-answers/", $file))
    };
}

fn read<T: DeserializeOwned>(answer: &str) -> T {
    decode("recorded", answer.to_owned()).unwrap()
}

fn numbered(id: u32) -> WorkspaceRef {
    WorkspaceRef {
        id: Some(WorkspaceId::try_from(id).unwrap()),
        kind: WorkspaceKind::Normal,
        address: id.to_string(),
        name: id.to_string(),
    }
}

fn scratch() -> WorkspaceRef {
    WorkspaceRef {
        id: None,
        kind: WorkspaceKind::Special,
        address: "special:scratch".into(),
        name: "special:scratch".into(),
    }
}

fn no_workspace() -> WorkspaceRef {
    WorkspaceRef {
        id: None,
        kind: WorkspaceKind::None,
        address: String::new(),
        name: String::new(),
    }
}

#[test]
fn monitor() {
    let monitors: Vec<Monitor> = read(recorded!("monitors-all.json"));
    let [monitor] = monitors.as_slice() else {
        panic!("{monitors:?}")
    };
    assert_eq!(monitor.id, MonitorId::new(0));
    assert_eq!(monitor.name, "Virtual-1");
    assert_eq!((monitor.width, monitor.height), (4096, 2160));
    assert!((monitor.refresh_rate - 60.0).abs() < f64::EPSILON);
    assert!((monitor.scale - 2.0).abs() < f64::EPSILON);
    assert_eq!(monitor.active_workspace, numbered(1));
    assert_eq!(monitor.special_workspace, no_workspace());
    assert_eq!(monitor.reserved.top, 0);
    assert_eq!(monitor.transform, Transform::Normal);
    assert_eq!(
        monitor.flags.iter().collect::<Vec<_>>(),
        [
            MonitorFlag::Focused,
            MonitorFlag::DpmsStatus,
            MonitorFlag::HardwareCursorsInUse
        ]
    );
    assert_eq!(monitor.solitary, None);
    assert_eq!(
        monitor.solitary_blocked_by,
        [SolitaryBlocker::Windowed, SolitaryBlocker::Candidate]
    );
    assert_eq!(monitor.tearing_blocked_by[0], TearingBlocker::NotTorn);
    assert_eq!(
        monitor.direct_scanout_blocked_by,
        [ScanoutBlocker::Software, ScanoutBlocker::Candidate]
    );
    assert_eq!(monitor.current_format, PixelFormat::Xrgb8888);
    assert_eq!(monitor.mirror_of, None);
    assert_eq!(monitor.available_modes.len(), 34);
    assert_eq!(
        monitor.available_modes[0],
        Mode {
            width: 1024,
            height: 768,
            refresh_rate_hz: 60.0
        }
    );
    assert_eq!(monitor.color_management_preset, ColorPreset::Srgb);
    assert_eq!(monitor.hardware_details.backend, Backend::Drm);
}

#[test]
fn disabled_monitor_has_no_workspace() {
    let monitors: Vec<Monitor> = read(recorded!("monitors-all-special-and-disabled.json"));
    let [enabled, disabled] = monitors.as_slice() else {
        panic!("{monitors:?}")
    };
    assert_eq!(enabled.active_workspace, numbered(3));
    assert_eq!(enabled.special_workspace, scratch());
    assert!(disabled.flags.contains(MonitorFlag::Disabled));
    assert_eq!(disabled.active_workspace, no_workspace());
    assert_eq!(disabled.special_workspace, no_workspace());
    assert_eq!(disabled.hardware_details.backend, Backend::Headless);
}

#[test]
fn special_workspace_on_a_second_output() {
    let monitors: Vec<Monitor> = read(recorded!("monitors-all-two-outputs-named-and-special.json"));
    let [first, second] = monitors.as_slice() else {
        panic!("{monitors:?}")
    };
    assert_eq!(first.active_workspace.kind, WorkspaceKind::Normal);
    assert_eq!(first.active_workspace.id, None);
    assert_eq!(first.active_workspace.address, "web");
    assert_eq!(second.name, "HEADLESS-2");
    assert!(!second.flags.contains(MonitorFlag::Disabled));
    assert_eq!(second.active_workspace, numbered(2));
    assert_eq!(second.special_workspace, scratch());
}

#[test]
fn named_workspace_on_a_monitor_beside_a_disabled_one() {
    let monitors: Vec<Monitor> = read(recorded!("monitors-all-named-special-and-disabled.json"));
    let [first, second] = monitors.as_slice() else {
        panic!("{monitors:?}")
    };
    assert_eq!(first.active_workspace.address, "web");
    assert_eq!(first.special_workspace, scratch());
    assert!(second.flags.contains(MonitorFlag::Disabled));
    assert_eq!(second.active_workspace, no_workspace());
}

#[test]
fn client() {
    let clients: Vec<Client> = read(recorded!("clients.json"));
    let [client] = clients.as_slice() else {
        panic!("{clients:?}")
    };
    assert_eq!(client.address.to_string(), "0x573106b0db30");
    assert_eq!(client.at, Position { x: 0, y: 0 });
    assert_eq!(
        client.size,
        Size {
            width: 2048,
            height: 1080
        }
    );
    assert_eq!(
        client.flags.iter().collect::<Vec<_>>(),
        [
            ClientFlag::Mapped,
            ClientFlag::Visible,
            ClientFlag::AcceptsInput,
            ClientFlag::AllowedOverFullscreen
        ]
    );
    assert_eq!(client.workspace, numbered(1));
    assert_eq!(client.monitor, Some(MonitorId::new(0)));
    assert_eq!(
        (client.class.as_str(), client.title.as_str()),
        ("foot", "terminal")
    );
    assert_eq!(client.fullscreen, FullscreenState::None);
    assert_eq!(client.fullscreen_handler, FullscreenHandler::Default);
    assert!(client.grouped.is_empty());
    assert_eq!(client.swallowing, None);
    assert_eq!(client.focus_history_id, Some(0));
    assert_eq!(client.content_type, ContentType::None);
    assert_eq!(client.stable_id, StableId(0x1800_0001));
}

#[test]
fn window_on_a_special_workspace() {
    for answer in [
        recorded!("clients-on-special.json"),
        recorded!("clients-special-on-second-output.json"),
    ] {
        let clients: Vec<Client> = read(answer);
        assert_eq!(clients[0].workspace, scratch());
    }
}

#[test]
fn active_window() {
    let client::ActiveWindow(window) = read(recorded!("activewindow.json"));
    let window = window.unwrap();
    assert_eq!(window.title, "terminal");
    assert_eq!(window.workspace, numbered(1));

    let client::ActiveWindow(on_special) = read(recorded!("activewindow-on-special.json"));
    let on_special = on_special.unwrap();
    assert_eq!(on_special.workspace, scratch());
    assert_eq!(on_special.at, Position { x: 2048, y: 0 });

    let client::ActiveWindow(none) = read(recorded!("activewindow-none.json"));
    assert_eq!(none, None);
}

#[test]
fn an_active_window_that_does_not_read_names_the_failed_field() {
    let broken = recorded!("activewindow.json").replace(r#""pid": 279661,"#, "");
    let result: Result<client::ActiveWindow> = decode("activewindow", broken);
    assert!(
        matches!(&result, Err(Error::Answer { source, .. }) if source.to_string().contains("missing field `pid`")),
        "{:?}",
        result.err()
    );
}

#[test]
fn workspaces() {
    let workspaces: Vec<Workspace> = read(recorded!("workspaces.json"));
    let [workspace] = workspaces.as_slice() else {
        panic!("{workspaces:?}")
    };
    assert_eq!(workspace.workspace, numbered(1));
    assert_eq!(workspace.monitor.as_deref(), Some("Virtual-1"));
    assert_eq!(workspace.monitor_id, Some(MonitorId::new(0)));
    assert_eq!(workspace.windows, 1);
    assert_eq!(workspace.last_window.unwrap().to_string(), "0x573106b0db30");
    assert_eq!(workspace.last_window_title, "terminal");
    assert_eq!(workspace.tiled_layout.as_deref(), Some("dwindle"));

    let active: Workspace = read(recorded!("activeworkspace.json"));
    assert_eq!(active, *workspace);
}

#[test]
fn special_and_named_workspaces_have_no_id() {
    let workspaces: Vec<Workspace> = read(recorded!("workspaces-with-special.json"));
    let special: Vec<_> = workspaces
        .iter()
        .filter(|w| w.workspace.id.is_none())
        .collect();
    assert_eq!(workspaces.len(), 10);
    assert_eq!(special.len(), 1);
    assert_eq!(special[0].workspace, scratch());
    assert!(
        workspaces
            .iter()
            .filter(|w| w.windows == 0)
            .all(|w| w.last_window.is_none())
    );

    for answer in [
        recorded!("workspaces-named-and-special.json"),
        recorded!("workspaces-named-special-and-disabled.json"),
    ] {
        let workspaces: Vec<Workspace> = read(answer);
        let named = workspaces
            .iter()
            .find(|w| w.workspace.address == "web")
            .unwrap();
        assert_eq!(named.workspace.id, None);
        assert_eq!(named.workspace.kind, WorkspaceKind::Normal);
        assert!(workspaces.iter().any(|w| w.workspace == scratch()));
    }
}

#[test]
fn workspace_rules() {
    let rules: Vec<WorkspaceRule> = read(recorded!("workspacerules.json"));
    assert_eq!(rules.len(), 3);
    assert_eq!(rules[0].workspace_string, "w[tv1]");
    assert_eq!(rules[0].monitor, None);
    assert_eq!(rules[0].border_size, None);
    let rule = &rules[2];
    assert_eq!(rule.workspace_string, "3");
    assert_eq!(rule.monitor.as_deref(), Some("Virtual-1"));
    assert_eq!((rule.default, rule.persistent), (Some(true), Some(true)));
    assert_eq!(rule.gaps_in.map(|gaps| gaps.left), Some(5));
    assert_eq!(rule.gaps_out.map(|gaps| gaps.top), Some(10));
    assert_eq!(rule.border_size, Some(3));
    assert_eq!((rule.border, rule.rounding), (Some(false), Some(true)));
    assert_eq!((rule.decorate, rule.shadow), (Some(true), Some(false)));
    assert_eq!(rule.default_name.as_deref(), Some("three"));
    assert_eq!(rule.on_created_empty, None);
}

#[test]
fn layers() {
    let layers: BTreeMap<String, MonitorLayers> = read(recorded!("layers.json"));
    let levels = &layers["Virtual-1"].levels;
    assert!(levels.background.is_empty() && levels.overlay.is_empty());
}

#[test]
fn layer_entry() {
    let layer: Layer = read(
        r#"{"address": "0x55d0c0ffee00", "x": 0, "y": 0, "w": 2048, "h": 32.5,
            "alpha": 1, "namespace": "topbar", "pid": 4242}"#,
    );
    assert_eq!(layer.namespace, "topbar");
    assert!((layer.height - 32.5).abs() < f64::EPSILON);
}

#[test]
fn devices() {
    let devices: Devices = read(recorded!("devices.json"));
    assert_eq!(devices.mice[0].name, "imexps/2-generic-explorer-mouse");
    assert_eq!(devices.mice[0].scroll_factor, None);
    let main: Vec<_> = devices.keyboards.iter().filter(|k| k.main).collect();
    assert_eq!(main.len(), 1);
    assert_eq!(main[0].active_keymap, "English (US)");
    assert_eq!(main[0].active_layout_index, 0);
    assert!(devices.tablets.is_empty() && devices.touch.is_empty());
}

/// Hyprland 0.57.1 writes `"active_layout_index": none` for a keyboard
/// without an active layout, which is not JSON.
#[test]
fn devices_with_a_keyboard_without_layout_fail_as_a_whole() {
    let answer = recorded!("devices.json").replacen(
        r#""active_layout_index": 0"#,
        r#""active_layout_index": none"#,
        1,
    );
    let result: Result<Devices> = decode("devices", answer.clone());
    assert!(
        matches!(&result, Err(Error::Refused { request, answer: returned }) if request == "devices" && *returned == answer),
        "{:?}",
        result.err()
    );
}

#[test]
fn tablet_devices() {
    let tablets: Vec<TabletDevice> = read(
        r#"[{"address": "0x1", "type": "tabletPad", "belongsTo": {"address": "0x2", "name": "pen"}},
            {"address": "0x3", "type": "tabletPad", "belongsTo": {"address": "0x0", "name": ""}},
            {"address": "0x2", "name": "pen"},
            {"address": "0x4", "type": "tabletTool"},
            {"address": "0x5", "type": "tabletDial"}]"#,
    );
    assert!(
        matches!(&tablets[0], TabletDevice::Pad { belongs_to: Some(tablet), .. } if tablet.name == "pen")
    );
    assert!(matches!(
        &tablets[1],
        TabletDevice::Pad {
            belongs_to: None,
            ..
        }
    ));
    assert!(matches!(&tablets[2], TabletDevice::Tablet(tablet) if tablet.name == "pen"));
    assert!(matches!(&tablets[3], TabletDevice::Tool { .. }));
    assert!(matches!(&tablets[4], TabletDevice::Unknown { .. }));
}

#[test]
fn a_pad_whose_tablet_does_not_read_fails_with_its_cause() {
    for (entry, cause) in [
        (
            r#"{"address": "0x1", "type": "tabletPad", "belongsTo": {"address": "2", "name": "pen"}}"#,
            "does not start with 0x",
        ),
        (r#"{"address": "0x1", "type": "tabletPad"}"#, "belongsTo"),
    ] {
        let result: Result<TabletDevice> = decode("devices", entry.to_owned());
        assert!(
            matches!(&result, Err(Error::Answer { source, .. }) if source.to_string().contains(cause)),
            "{:?}",
            result.err()
        );
    }
}

#[test]
fn cursor_position() {
    let device::CursorPosition(cursor) = read(recorded!("cursorpos.json"));
    assert_eq!(cursor, Position { x: 256, y: 192 });
}

#[test]
fn binds() {
    let binds: Vec<Bind> = read(recorded!("binds.json"));
    assert_eq!(binds.len(), 5);
    let described = &binds[1];
    assert!(described.flags.contains(BindFlag::Repeat));
    assert!(described.flags.contains(BindFlag::HasDescription));
    assert_eq!(described.description.as_deref(), Some("Focus left"));
    assert_eq!(
        described.modifiers.iter().collect::<Vec<_>>(),
        [Modifier::Shift, Modifier::Super]
    );
    assert_eq!(
        binds[2].flags.iter().collect::<Vec<_>>(),
        [BindFlag::Locked, BindFlag::Release]
    );
    assert!(binds[3].flags.contains(BindFlag::Mouse));
    assert_eq!(binds[3].key, BindKey::Name("mouse:272".into()));
    assert_eq!(binds[0].submap, None);
    assert_eq!(binds[4].submap.as_deref(), Some("resize"));
    assert!(binds[4].flags.contains(BindFlag::NonConsuming));
    assert!(binds.iter().all(|bind| !bind.submap_universal));
}

#[test]
fn animations() {
    let animations: Animations = read(recorded!("animations.json"));
    assert!(
        animations
            .animations
            .iter()
            .any(|leaf| leaf.name == "windows")
    );
    let curve = animations
        .beziers
        .iter()
        .find(|curve| curve.name == "myBezier")
        .unwrap();
    assert!((curve.y1 - 1.02).abs() < f64::EPSILON);
}

#[test]
fn option_values() {
    let value = |answer| read::<ConfigOption>(answer).value;
    assert_eq!(value(recorded!("getoption-int.json")), OptionValue::Int(2));
    assert_eq!(
        value(recorded!("getoption-bool.json")),
        OptionValue::Bool(true)
    );
    assert_eq!(
        value(recorded!("getoption-float.json")),
        OptionValue::Float(0.0)
    );
    assert_eq!(
        value(recorded!("getoption-str.json")),
        OptionValue::Str("dwindle".into())
    );
    assert_eq!(
        value(recorded!("getoption-css.json")),
        OptionValue::Css("2 2 2 2".into())
    );
    assert_eq!(
        value(recorded!("getoption-gradient.json")),
        OptionValue::Gradient("ee00b4e7 ee00ff99 45deg".into())
    );
    assert_eq!(
        value(recorded!("getoption-vec2.json")),
        OptionValue::Vec2([0.0, 0.0])
    );

    let option: ConfigOption = read(recorded!("getoption-vec2.json"));
    assert_eq!(option.option, "decoration:shadow:offset");
    assert!(!option.set);
}

#[test]
fn config_errors() {
    let none: config::ConfigErrors = read(recorded!("configerrors-none.json"));
    assert!(Vec::from(none).is_empty());
    let errors: config::ConfigErrors = read(recorded!("configerrors.json"));
    assert_eq!(Vec::from(errors), ["=[C]:-1: Invalid size"]);
}

#[test]
fn small_answers() {
    assert_eq!(read::<String>(recorded!("submap.json")), "default");
    assert!(!read::<system::Locked>(recorded!("locked.json")).locked);
    let status: Status = read(recorded!("status.json"));
    assert_eq!(status.config_provider, ConfigProvider::Lua);
    assert_eq!(status.backend, SessionBackend::Drm);
}

#[test]
fn version() {
    let version: Version = read(recorded!("version.json"));
    assert_eq!(version.version, "0.57.1");
    assert_eq!(version.tag, "v0.57.1");
    assert!(!version.dirty);
    assert_eq!(version.flags, [BuildFlag::Nix]);
    assert_eq!(version.commits, None);
    assert_eq!(version.system_hyprlang, "unknown");
}

#[test]
fn text_that_is_not_json_is_a_refusal() {
    for (request, answer) in [
        ("activeworkspace", "unsafe state"),
        ("getoption typo:name", "no such option"),
        ("activeworkspace", ""),
    ] {
        let result: Result<Workspace> = decode(request, answer.to_owned());
        assert!(
            matches!(
                &result,
                Err(Error::Refused { request: sent, answer: returned })
                    if sent == request && returned == answer
            ),
            "{result:?}"
        );
    }
}

#[test]
fn json_of_another_form_is_an_answer_error() {
    let result: Result<Workspace> = decode("activeworkspace", "[]".to_owned());
    assert!(
        matches!(&result, Err(Error::Answer { request, answer, .. }) if request == "activeworkspace" && answer == "[]"),
        "{result:?}"
    );
}

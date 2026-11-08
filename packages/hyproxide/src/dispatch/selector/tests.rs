use super::*;

fn text(value: impl Into<Value>) -> String {
    match value.into() {
        Value::String(text) => text,
        other => panic!("{other:?} is not a string"),
    }
}

fn id(number: u32) -> WorkspaceId {
    WorkspaceId::try_from(number).unwrap()
}

fn position(number: u32) -> NonZeroU32 {
    NonZeroU32::new(number).unwrap()
}

fn reference(id: Option<u32>, kind: WorkspaceKind, address: &str) -> WorkspaceRef {
    WorkspaceRef {
        id: id.map(self::id),
        kind,
        address: address.to_owned(),
        name: address.to_owned(),
    }
}

#[test]
fn window_selectors() {
    let address = Address::new(0x55d0_c0ff_ee00.try_into().unwrap());
    assert_eq!(text(WindowSelector::Active), "active");
    assert_eq!(text(WindowSelector::Floating), "floating");
    assert_eq!(text(WindowSelector::Tiled), "tiled");
    assert_eq!(text(WindowSelector::Class("^foot$".into())), "class:^foot$");
    assert_eq!(
        text(WindowSelector::InitialClass("a".into())),
        "initialclass:a"
    );
    assert_eq!(text(WindowSelector::Title("b".into())), "title:b");
    assert_eq!(
        text(WindowSelector::InitialTitle("c".into())),
        "initialtitle:c"
    );
    assert_eq!(text(WindowSelector::Tag("d".into())), "tag:d");
    assert_eq!(
        text(WindowSelector::StableId(StableId(0x1800_0001))),
        "stableid:18000001"
    );
    assert_eq!(
        text(WindowSelector::from(address)),
        "address:0x55d0c0ffee00"
    );
    assert_eq!(text(WindowSelector::Pid(42)), "pid:42");
}

#[test]
fn workspace_selectors() {
    let empty = |on_monitor, after_active| WorkspaceSelector::Empty {
        on_monitor,
        after_active,
    };
    assert_eq!(text(WorkspaceSelector::from(id(13))), "13");
    let web = WorkspaceName::try_from("web").unwrap();
    assert_eq!(text(WorkspaceSelector::Named(web)), "name:web");
    assert_eq!(
        text(WorkspaceSelector::Special("scratch".into())),
        "special:scratch"
    );
    assert_eq!(text(empty(false, false)), "empty");
    assert_eq!(text(empty(true, true)), "emptymn");
    assert_eq!(text(WorkspaceSelector::Previous), "previous");
    assert_eq!(
        text(WorkspaceSelector::PreviousOnMonitor),
        "previous_per_monitor"
    );
    assert_eq!(text(WorkspaceSelector::Next), "next");
    assert_eq!(text(WorkspaceSelector::Offset(2)), "+2");
    assert_eq!(text(WorkspaceSelector::Offset(-1)), "-1");
    assert_eq!(text(WorkspaceSelector::MonitorOffset(-3)), "r-3");
    assert_eq!(text(WorkspaceSelector::MonitorPosition(position(4))), "r~4");
    let open_offset = WorkspaceSelector::OpenOffset {
        scope: MonitorScope::All,
        offset: 1,
    };
    assert_eq!(text(open_offset), "e+1");
    let open_position = WorkspaceSelector::OpenPosition {
        scope: MonitorScope::Focused,
        position: position(2),
    };
    assert_eq!(text(open_position), "m~2");
}

#[test]
fn workspace_names_are_not_numbers() {
    assert!(WorkspaceName::try_from("web 2").is_ok());
    assert!(WorkspaceName::try_from("2web").is_ok());
    for name in ["", "2", "0042"] {
        assert_eq!(
            WorkspaceName::try_from(name),
            Err(NotAWorkspaceName(name.to_owned()))
        );
    }
}

#[test]
fn workspaces_from_answers_are_selected_by_their_identity() {
    let of = |workspace| WorkspaceSelector::of(&workspace).unwrap();
    assert_eq!(
        of(reference(Some(6), WorkspaceKind::Normal, "6")),
        Some(WorkspaceSelector::Id(id(6)))
    );
    assert_eq!(
        of(reference(None, WorkspaceKind::Special, "special:scratch")),
        Some(WorkspaceSelector::Special("scratch".into()))
    );
    // A named workspace can be called `special:foo` and is a normal one.
    assert_eq!(
        of(reference(None, WorkspaceKind::Normal, "special:foo")),
        Some(WorkspaceSelector::Named(
            WorkspaceName::try_from("special:foo").unwrap()
        ))
    );
    assert_eq!(of(reference(None, WorkspaceKind::None, "")), None);
}

#[test]
fn a_workspace_whose_address_does_not_fit_its_kind_has_no_selector() {
    for workspace in [
        reference(None, WorkspaceKind::Special, "scratch"),
        reference(None, WorkspaceKind::Normal, "7"),
    ] {
        assert_eq!(
            WorkspaceSelector::of(&workspace),
            Err(MalformedWorkspace {
                address: workspace.address.clone()
            })
        );
    }
}

#[test]
fn monitor_selectors() {
    assert_eq!(text(MonitorSelector::Current), "current");
    assert_eq!(text(MonitorSelector::Direction(Direction::Up)), "up");
    assert_eq!(text(MonitorSelector::Offset(1)), "+1");
    assert_eq!(text(MonitorSelector::from(MonitorId::new(2))), "2");
    assert_eq!(text(MonitorSelector::Name("DP-1".into())), "DP-1");
    assert_eq!(text(MonitorSelector::Description("BNQ".into())), "desc:BNQ");
}

#[test]
fn directions_and_actions() {
    assert_eq!(text(Direction::Left), "left");
    assert_eq!(text(Direction::Down), "down");
    assert_eq!(text(Action::Toggle), "toggle");
    assert_eq!(text(Action::Enable), "enable");
    assert_eq!(text(Action::Disable), "disable");
}

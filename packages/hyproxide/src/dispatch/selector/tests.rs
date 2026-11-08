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
fn workspaces_from_answers_and_events_are_selected_by_their_address() {
    let web = WorkspaceName::try_from("web").unwrap();
    for (address, selector) in [
        (
            WorkspaceAddress::Numbered(id(6)),
            Some(WorkspaceSelector::Id(id(6))),
        ),
        (
            WorkspaceAddress::Named(web.clone()),
            Some(WorkspaceSelector::Named(web)),
        ),
        (
            WorkspaceAddress::Special("scratch".into()),
            Some(WorkspaceSelector::Special("scratch".into())),
        ),
        (WorkspaceAddress::None, None),
    ] {
        assert_eq!(WorkspaceSelector::of(&address), selector, "{address:?}");
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

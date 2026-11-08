use super::*;
use crate::address::Address;
use crate::dispatch::lua;
use crate::workspace::WorkspaceId;

fn workspace(number: u32) -> WorkspaceSelector {
    WorkspaceId::try_from(number).unwrap().into()
}

fn address() -> Address {
    Address::new(0x55d0_c0ff_ee00.try_into().unwrap())
}

#[test]
fn close_kill_signal() {
    assert_eq!(lua(close()), "hl.dsp.window.close({})");
    assert_eq!(
        lua(close().window(address())),
        r#"hl.dsp.window.close({ window = "address:0x55d0c0ffee00" })"#
    );
    assert_eq!(lua(kill()), "hl.dsp.window.kill({})");
    assert_eq!(
        lua(signal(15).window(WindowSelector::Pid(7))),
        r#"hl.dsp.window.signal({ signal = 15, window = "pid:7" })"#
    );
}

#[test]
fn switches() {
    assert_eq!(lua(float()), "hl.dsp.window.float({})");
    assert_eq!(
        lua(float().action(Action::Enable)),
        r#"hl.dsp.window.float({ action = "enable" })"#
    );
    assert_eq!(
        lua(pseudo().action(Action::Toggle)),
        r#"hl.dsp.window.pseudo({ action = "toggle" })"#
    );
    assert_eq!(
        lua(pin().action(Action::Disable).window(WindowSelector::Active)),
        r#"hl.dsp.window.pin({ action = "disable", window = "active" })"#
    );
    assert_eq!(
        lua(deny_from_group().action(Action::Enable)),
        r#"hl.dsp.window.deny_from_group({ action = "enable" })"#
    );
}

#[test]
fn fullscreen_dispatchers() {
    assert_eq!(lua(fullscreen()), "hl.dsp.window.fullscreen({})");
    assert_eq!(
        lua(fullscreen()
            .mode(FullscreenMode::Maximized)
            .action(FullscreenAction::Set)
            .layout_aware(false)),
        r#"hl.dsp.window.fullscreen({ mode = "maximized", action = "set", layout_aware = false })"#
    );
    assert_eq!(
        lua(
            fullscreen_state(FullscreenState::Fullscreen, FullscreenState::None)
                .action(FullscreenAction::Unset)
        ),
        "hl.dsp.window.fullscreen_state({ internal = 2, client = 0, action = \"unset\" })"
    );
}

#[test]
fn movements() {
    let movement = |movement| lua(move_window(movement));
    assert_eq!(
        movement(Movement::Direction {
            direction: Direction::Left,
            group_aware: true
        }),
        r#"hl.dsp.window.move({ direction = "left", group_aware = true })"#
    );
    assert_eq!(
        movement(Movement::Position {
            x: 10.0,
            y: -2.5,
            relative: true
        }),
        "hl.dsp.window.move({ x = 10, y = -2.5, relative = true })"
    );
    assert_eq!(
        lua(move_window(Movement::Workspace {
            workspace: workspace(21),
            follow: false
        })
        .window(address())),
        r#"hl.dsp.window.move({ workspace = "21", follow = false, window = "address:0x55d0c0ffee00" })"#
    );
    assert_eq!(
        movement(Movement::Monitor {
            monitor: MonitorSelector::Name("DP-1".into()),
            follow: true
        }),
        r#"hl.dsp.window.move({ monitor = "DP-1", follow = true })"#
    );
    assert_eq!(
        movement(Movement::IntoGroup(Direction::Up)),
        r#"hl.dsp.window.move({ into_group = "up" })"#
    );
    assert_eq!(
        movement(Movement::IntoOrCreateGroup(Direction::Down)),
        r#"hl.dsp.window.move({ into_or_create_group = "down" })"#
    );
    assert_eq!(
        movement(Movement::OutOfGroup(Some(Direction::Right))),
        r#"hl.dsp.window.move({ out_of_group = "right" })"#
    );
    assert_eq!(
        movement(Movement::OutOfGroup(None)),
        "hl.dsp.window.move({ out_of_group = true })"
    );
}

#[test]
fn swaps() {
    assert_eq!(
        lua(swap(Swap::Direction(Direction::Right))),
        r#"hl.dsp.window.swap({ direction = "right" })"#
    );
    assert_eq!(
        lua(swap(Swap::With(WindowSelector::Title("^mail$".into()))).window(address())),
        r#"hl.dsp.window.swap({ target = "title:^mail$", window = "address:0x55d0c0ffee00" })"#
    );
    assert_eq!(lua(swap(Swap::Next)), "hl.dsp.window.swap({ next = true })");
    assert_eq!(
        lua(swap(Swap::Previous)),
        "hl.dsp.window.swap({ prev = true })"
    );
}

#[test]
fn placement() {
    assert_eq!(lua(center()), "hl.dsp.window.center({})");
    assert_eq!(
        lua(cycle_next().next(false).tiled(true).floating(false)),
        "hl.dsp.window.cycle_next({ next = false, tiled = true, floating = false })"
    );
    assert_eq!(lua(toggle_swallow()), "hl.dsp.window.toggle_swallow()");
    assert_eq!(lua(bring_to_top()), "hl.dsp.window.bring_to_top()");
    assert_eq!(
        lua(alter_zorder(ZOrder::Bottom)),
        r#"hl.dsp.window.alter_zorder({ mode = "bottom" })"#
    );
    assert_eq!(lua(drag()), "hl.dsp.window.drag()");
}

#[test]
fn tags_and_props() {
    assert_eq!(lua(tag("+work")), r#"hl.dsp.window.tag({ tag = "+work" })"#);
    assert_eq!(lua(clear_tags()), "hl.dsp.window.clear_tags({})");
    assert_eq!(
        lua(set_prop("opacity", "0.8")),
        r#"hl.dsp.window.set_prop({ prop = "opacity", value = "0.8" })"#
    );
}

#[test]
fn resizes() {
    assert_eq!(
        lua(resize(-20.0, 0.0).relative(true)),
        "hl.dsp.window.resize({ x = -20, y = 0, relative = true })"
    );
    assert_eq!(lua(mouse_resize(None)), "hl.dsp.window.resize()");
    assert_eq!(
        lua(mouse_resize(Some(true))),
        "hl.dsp.window.resize({ keep_aspect_ratio = true })"
    );
}

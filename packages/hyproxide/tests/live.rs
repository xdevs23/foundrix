//! Requests against a Hyprland 0.57 started by each test for itself, with a
//! runtime directory of its own, so no test reaches the Hyprland of a
//! desktop session.
//!
//! Hyprland takes over the display of the machine, so these tests run one at
//! a time, and only in the NixOS VM check `hyproxide-live`.

mod support;

use std::fs::{self, Permissions};
use std::future::Future;
use std::num::NonZeroU32;
use std::os::unix::fs::PermissionsExt as _;
use std::panic;
use std::process::Stdio;
use std::time::Duration;

use hyproxide::dispatch::command::{self, Color, Command, Icon, Notification, OutputBackend};
use hyproxide::dispatch::{
    self, Action, Direction, Dispatcher, Focus, KeyState, MonitorSelector, WindowSelector,
    WorkspaceName, WorkspaceSelector, cursor, group, window, workspace,
};
use hyproxide::keyboard::Modifier;
use hyproxide::window::FullscreenState;
use hyproxide::workspace::WorkspaceId;
use hyproxide::{Error, Instance, Word, query};
use tokio::net::UnixDatagram;
use tokio::process::Child;

use support::TempDirectory;

/// The configuration of every Hyprland a test starts. The update news and
/// donation screens are off, so no window opens that the tests did not open.
const CONFIG: &str = "hl.config({
    ecosystem = { no_update_news = true, no_donation_nag = true },
})
";

/// A headless Hyprland that runs until [`Hyprland::stop`], or until it is
/// dropped.
struct Hyprland {
    process: Child,
    instance: Instance,
    _runtime_directory: TempDirectory,
}

impl Hyprland {
    /// Start Hyprland and wait until it reports to be ready, through the
    /// `READY=1` message of the systemd notify protocol, which Hyprland sends
    /// after it opened its sockets.
    async fn start() -> Self {
        let runtime_directory = TempDirectory::new();
        let runtime = runtime_directory.path();
        fs::set_permissions(runtime, Permissions::from_mode(0o700)).unwrap();
        let config = runtime.join("hyprland.lua");
        fs::write(&config, CONFIG).unwrap();
        let notify_socket = runtime.join("notify.sock");
        let notifications = UnixDatagram::bind(&notify_socket).unwrap();

        let mut process = tokio::process::Command::new("Hyprland")
            .arg("--config")
            .arg(&config)
            // The VM runs the tests as root.
            .arg("--i-am-really-stupid")
            .env("XDG_RUNTIME_DIR", runtime)
            // Hyprland writes the version it last ran and the date of the
            // last donation screen into the data home, and crash reports
            // into the cache home. Both then lie in the runtime directory.
            .env("HOME", runtime)
            .env_remove("XDG_DATA_HOME")
            .env_remove("XDG_CACHE_HOME")
            .env("NOTIFY_SOCKET", &notify_socket)
            // Hyprland then does not export its environment to systemd and
            // D-Bus, and does not start hyprland-session.target, either of
            // which would change the session of the person who runs the tests.
            .env("HYPRLAND_NO_SD_VARS", "1")
            // Hyprland then does not open a window in a running session.
            .env_remove("WAYLAND_DISPLAY")
            .stdout(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .expect("starting Hyprland from PATH failed");

        tokio::select! {
            () = ready(&notifications) => {}
            exited = process.wait() => panic!("Hyprland exited before it was ready: {exited:?}"),
        }

        let instances: Vec<_> = fs::read_dir(runtime.join("hypr"))
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .collect();
        let [directory] = instances.as_slice() else {
            panic!("expected one instance directory, found {instances:?}")
        };
        Self {
            instance: Instance::at(directory),
            process,
            _runtime_directory: runtime_directory,
        }
    }

    /// Stop Hyprland and wait until it exited, so the next one can take over
    /// the display.
    async fn stop(mut self) {
        self.process.kill().await.unwrap();
    }
}

/// Wait for a notify message that contains `READY=1`. Hyprland and the
/// libraries it uses also send other messages, such as `ERRNO=2`.
async fn ready(notifications: &UnixDatagram) {
    loop {
        let mut message = Vec::new();
        let _length: usize = notifications.recv_buf(&mut message).await.unwrap();
        if message
            .split(|&byte| byte == b'\n')
            .any(|line| line == b"READY=1")
        {
            return;
        }
    }
}

/// Run a test against a Hyprland of its own, and stop that Hyprland also
/// when the test fails.
async fn with_hyprland<F, T>(test: F)
where
    F: FnOnce(Instance) -> T,
    T: Future<Output = ()> + Send + 'static,
{
    let hyprland = Hyprland::start().await;
    let outcome = tokio::spawn(test(hyprland.instance.clone())).await;
    hyprland.stop().await;
    if let Err(failure) = outcome {
        panic::resume_unwind(failure.into_panic());
    }
}

fn word(text: &str) -> Word {
    Word::try_from(text).unwrap()
}

fn id(number: u32) -> WorkspaceId {
    WorkspaceId::try_from(number).unwrap()
}

#[tokio::test]
async fn every_query_reads_its_answer() {
    with_hyprland(|instance| async move {
        let instance = &instance;
        let monitors = query::monitors(instance).await.unwrap();
        let monitor = monitors.first().expect("Hyprland reports a monitor");
        let _windows = query::clients(instance).await.unwrap();
        let _focused_window = query::active_window(instance).await.unwrap();
        let workspaces = query::workspaces(instance).await.unwrap();
        let active = query::active_workspace(instance).await.unwrap();
        assert!(workspaces.contains(&active));
        let _rules = query::workspace_rules(instance).await.unwrap();
        let layers = query::layers(instance).await.unwrap();
        assert!(layers.contains_key(&monitor.name));
        let _devices = query::devices(instance).await.unwrap();
        let _cursor = query::cursor_position(instance).await.unwrap();
        let _binds = query::binds(instance).await.unwrap();
        let _animations = query::animations(instance).await.unwrap();
        let option = query::option(instance, &word("general:border_size"))
            .await
            .unwrap();
        assert!(matches!(option.value, query::OptionValue::Int(_)));
        let _errors = query::config_errors(instance).await.unwrap();
        assert_eq!(query::submap(instance).await.unwrap(), "default");
        assert!(!query::locked(instance).await.unwrap());
        let version = query::version(instance).await.unwrap();
        assert!(version.version.starts_with("0.57"), "{version:?}");
        let _status = query::status(instance).await.unwrap();
    })
    .await;
}

#[tokio::test]
async fn dispatchers_are_answered_ok() {
    with_hyprland(|instance| async move {
        let start = query::active_workspace(&instance).await.unwrap().workspace;
        let selector = || WorkspaceSelector::of(&start).unwrap().unwrap();
        let dispatchers: Vec<Dispatcher> = vec![
            Focus::Workspace {
                workspace: id(4).into(),
                on_current_monitor: false,
            }
            .into(),
            Focus::Workspace {
                workspace: selector(),
                on_current_monitor: false,
            }
            .into(),
            window::float().action(Action::Toggle).into(),
            window::float().action(Action::Toggle).into(),
            workspace::toggle_special(Some("hyproxide")),
            workspace::toggle_special(Some("hyproxide")),
            workspace::rename(selector()).name("hyproxide").into(),
            workspace::rename(selector()).into(),
            group::toggle().into(),
            group::toggle().into(),
            cursor::move_to(100.0, 100.0),
            dispatch::event("hyproxide"),
            dispatch::exec_cmd("true"),
            dispatch::no_op(),
            Focus::Monitor(MonitorSelector::Current).into(),
            Focus::Workspace {
                workspace: WorkspaceSelector::Previous,
                on_current_monitor: false,
            }
            .into(),
            Focus::Workspace {
                workspace: WorkspaceSelector::Previous,
                on_current_monitor: false,
            }
            .into(),
        ];
        for dispatcher in dispatchers {
            let sent = dispatch::dispatch(&instance, dispatcher.clone()).await;
            assert!(sent.is_ok(), "{}: {sent:?}", dispatcher.as_lua());
        }
        let end = query::active_workspace(&instance).await.unwrap().workspace;
        assert_eq!(end, start);
    })
    .await;
}

#[tokio::test]
async fn dpms_switches_a_monitor_read_from_hyprland() {
    with_hyprland(|instance| async move {
        let monitors = query::monitors(&instance).await.unwrap();
        let dpms = dispatch::dpms()
            .action(Action::Enable)
            .monitor(monitors[0].id);
        let sent = dispatch::dispatch(&instance, dpms).await;
        assert!(sent.is_ok(), "{sent:?}");
    })
    .await;
}

#[tokio::test]
async fn lua_and_commands_are_answered_ok() {
    with_hyprland(|instance| async move {
        dispatch::eval(
            &instance,
            r#"hl.workspace_rule({ workspace = "9", persistent = false })"#,
        )
        .await
        .unwrap();

        let commands = [
            Command::Notify(Notification {
                icon: Icon::Info,
                duration: Duration::from_millis(500),
                color: Color {
                    red: 0x1e,
                    green: 0x88,
                    blue: 0xe5,
                    alpha: 0xff,
                },
                font_size: Some(14),
                message: "hyproxide says hello".into(),
            }),
            Command::DismissNotifications(None),
            Command::CreateOutput {
                backend: OutputBackend::Headless,
                name: Some(word("HYPROXIDE-1")),
            },
            Command::RemoveOutput(word("HYPROXIDE-1")),
        ];
        for request in commands {
            let ran = command::run(&instance, &request).await;
            assert!(ran.is_ok(), "{request}: {ran:?}");
        }
    })
    .await;
}

#[tokio::test]
async fn refused_requests_contain_the_answer() {
    with_hyprland(|instance| async move {
        let refused = dispatch::dispatch(
            &instance,
            Focus::Monitor(MonitorSelector::Name("NO-SUCH-MONITOR".into())),
        )
        .await;
        assert!(
            matches!(&refused, Err(Error::Refused { answer, .. }) if answer.starts_with("warning:")),
            "{refused:?}"
        );
        let refused = dispatch::eval(&instance, "error(\"boom\")").await;
        assert!(matches!(refused, Err(Error::Refused { .. })), "{refused:?}");
        let refused = command::run(&instance, &Command::RemoveOutput(word("NO-SUCH-OUTPUT"))).await;
        assert!(
            matches!(&refused, Err(Error::Refused { answer, .. }) if answer == "output not found"),
            "{refused:?}"
        );
        let refused = query::option(&instance, &word("no:such_option")).await;
        assert!(
            matches!(&refused, Err(Error::Refused { answer, .. }) if answer == "no such option"),
            "{refused:?}"
        );
    })
    .await;
}

#[tokio::test]
async fn config_errors_are_those_of_the_last_eval_or_dispatch() {
    with_hyprland(|instance| async move {
        let failed = dispatch::eval(&instance, "hl.config({ no_such_section = { x = 1 } })").await;
        assert!(matches!(failed, Err(Error::Refused { .. })), "{failed:?}");
        let errors = query::config_errors(&instance).await.unwrap();
        assert!(
            errors.iter().any(|error| error.contains("no_such_section")),
            "{errors:?}"
        );

        dispatch::dispatch(&instance, dispatch::no_op())
            .await
            .unwrap();
        assert_eq!(
            query::config_errors(&instance).await.unwrap(),
            Vec::<String>::new()
        );
    })
    .await;
}

fn some_window() -> WindowSelector {
    WindowSelector::Class("^no-such-window$".into())
}

fn some_workspace() -> WorkspaceSelector {
    WorkspaceSelector::Named(WorkspaceName::try_from("hyproxide").unwrap())
}

fn some_monitor() -> MonitorSelector {
    MonitorSelector::Name("NO-SUCH-MONITOR".into())
}

/// Every dispatcher builder, with its optional fields set. `eval` builds a
/// dispatcher without running it, and Hyprland returns an error for a
/// dispatcher it cannot build.
fn every_dispatcher() -> Vec<Dispatcher> {
    let mut dispatchers = window_dispatchers();
    dispatchers.extend(dispatchers_with_one_of_several_forms());
    dispatchers.extend(other_dispatchers());
    dispatchers
}

fn window_dispatchers() -> Vec<Dispatcher> {
    vec![
        window::close().window(some_window()).into(),
        window::kill().window(some_window()).into(),
        window::signal(0).window(some_window()).into(),
        window::float()
            .action(Action::Enable)
            .window(some_window())
            .into(),
        window::pseudo()
            .action(Action::Disable)
            .window(some_window())
            .into(),
        window::pin()
            .action(Action::Toggle)
            .window(some_window())
            .into(),
        window::fullscreen()
            .mode(window::FullscreenMode::Maximized)
            .action(window::FullscreenAction::Set)
            .layout_aware(false)
            .window(some_window())
            .into(),
        window::fullscreen_state(FullscreenState::Fullscreen, FullscreenState::None)
            .action(window::FullscreenAction::Unset)
            .layout_aware(true)
            .window(some_window())
            .into(),
        window::center().window(some_window()).into(),
        window::cycle_next()
            .next(false)
            .tiled(true)
            .floating(false)
            .window(some_window())
            .into(),
        window::tag("+hyproxide").window(some_window()).into(),
        window::clear_tags().window(some_window()).into(),
        window::toggle_swallow(),
        window::bring_to_top(),
        window::alter_zorder(window::ZOrder::Top)
            .window(some_window())
            .into(),
        window::set_prop("opacity", "0.5")
            .window(some_window())
            .into(),
        window::deny_from_group().action(Action::Enable).into(),
        window::drag(),
        window::resize(10.0, 10.0)
            .relative(true)
            .window(some_window())
            .into(),
        window::mouse_resize(None),
        window::mouse_resize(Some(true)),
    ]
}

fn other_dispatchers() -> Vec<Dispatcher> {
    vec![
        group::toggle().window(some_window()).into(),
        group::next().window(some_window()).into(),
        group::prev().window(some_window()).into(),
        group::active(NonZeroU32::MIN).window(some_window()).into(),
        group::move_window().forward(false).into(),
        group::lock()
            .action(Action::Enable)
            .window(some_window())
            .into(),
        group::lock_all().action(Action::Disable).into(),
        workspace::rename(some_workspace()).name("shown").into(),
        workspace::change_id(some_workspace(), id(99)),
        workspace::move_to_monitor(some_monitor())
            .workspace(some_workspace())
            .into(),
        workspace::swap_monitors(MonitorSelector::Current, some_monitor()),
        workspace::toggle_special(Some("hyproxide")),
        workspace::toggle_special(None),
        cursor::move_to_corner(cursor::Corner::TopRight)
            .window(some_window())
            .into(),
        cursor::move_to(1.0, 1.0),
        dispatch::exec_cmd("true"),
        dispatch::exec_raw("true"),
        dispatch::exit(),
        dispatch::reload_config(),
        dispatch::submap("reset"),
        dispatch::pass(some_window()),
        dispatch::send_shortcut([Modifier::Super].into_iter().collect(), "Return")
            .window(some_window())
            .into(),
        dispatch::send_key_state(Modifier::Ctrl.into(), "code:36", KeyState::Repeat)
            .window(some_window())
            .into(),
        dispatch::layout("togglesplit"),
        dispatch::dpms().action(Action::Enable).into(),
        dispatch::event("hyproxide"),
        dispatch::global("org.example", "record"),
        dispatch::force_renderer_reload(),
        dispatch::force_idle(Duration::from_secs(1)),
        dispatch::release_input_capture(),
        dispatch::no_op(),
    ]
}

fn dispatchers_with_one_of_several_forms() -> Vec<Dispatcher> {
    let movements = [
        window::Movement::Direction {
            direction: Direction::Left,
            group_aware: true,
        },
        window::Movement::Position {
            x: 1.0,
            y: 2.5,
            relative: true,
        },
        window::Movement::Workspace {
            workspace: some_workspace(),
            follow: false,
        },
        window::Movement::Monitor {
            monitor: some_monitor(),
            follow: true,
        },
        window::Movement::IntoGroup(Direction::Up),
        window::Movement::IntoOrCreateGroup(Direction::Down),
        window::Movement::OutOfGroup(Some(Direction::Right)),
        window::Movement::OutOfGroup(None),
    ];
    let swaps = [
        window::Swap::Direction(Direction::Left),
        window::Swap::With(some_window()),
        window::Swap::Next,
        window::Swap::Previous,
    ];
    let focuses = [
        Focus::Direction(Direction::Down),
        Focus::Monitor(some_monitor()),
        Focus::Workspace {
            workspace: some_workspace(),
            on_current_monitor: true,
        },
        Focus::Window(some_window()),
        Focus::UrgentOrLast,
        Focus::Last,
    ];
    let moves =
        movements.map(|movement| window::move_window(movement).window(some_window()).into());
    let swaps = swaps.map(|swap| window::swap(swap).window(some_window()).into());
    let focuses = focuses.map(Dispatcher::from);
    moves.into_iter().chain(swaps).chain(focuses).collect()
}

#[tokio::test]
async fn every_dispatcher_is_built_by_hyprland() {
    with_hyprland(|instance| async move {
        for dispatcher in every_dispatcher() {
            let built = dispatch::eval(&instance, dispatcher.as_lua()).await;
            assert!(built.is_ok(), "{}: {built:?}", dispatcher.as_lua());
        }
    })
    .await;
}

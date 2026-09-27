//! Requests sent to Hyprland's command socket.
//!
//! With a Lua configuration, Hyprland runs the text of a `dispatch` request as
//! the argument of `hl.dispatch(...)` and the text of an `eval` request as Lua
//! code. Each [`Request`] variant renders one of those forms from typed values,
//! and [`Request::send`] writes it to Hyprland's command socket.
//!
//! Every request, the commands here and the state queries alike, goes through
//! [`exchange`]. Hyprland queues at most 10 connections on its command socket,
//! and a connect that does not wait fails with `EAGAIN` while that queue is
//! full. [`exchange`] connects so that the kernel waits for room instead.

use std::ffi::OsString;
use std::fmt::Write as _;
use std::io;
use std::os::fd::OwnedFd;
use std::path::{Path, PathBuf};
use std::time::Duration;

use hyprland::shared::{Address, WorkspaceId};
use socket2::{Domain, SockAddr, Socket, Type};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;

use crate::error::{Error, Result};

/// How long a connect waits for room in Hyprland's request queue. Hyprland
/// waits as long for the request of a client it has accepted.
const CONNECT_WAIT: Duration = Duration::from_secs(5);

/// One command for Hyprland.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Request<'a> {
    /// Focus a workspace on the monitor that holds it.
    FocusWorkspace(WorkspaceId),
    /// Move a window to a workspace without following it.
    MoveWindowSilent {
        window: &'a Address,
        workspace: WorkspaceId,
    },
    /// Move a window to a workspace and follow it.
    MoveWindow {
        window: &'a Address,
        workspace: WorkspaceId,
    },
    /// Move the active window to a workspace and follow it.
    MoveActiveWindow(WorkspaceId),
    /// Move a workspace to a monitor.
    MoveWorkspaceToMonitor {
        workspace: WorkspaceId,
        monitor: &'a str,
    },
    /// Focus a window.
    FocusWindow(&'a Address),
    /// Bind a workspace to a monitor as a persistent workspace. A rule for a
    /// workspace that already has one replaces it.
    WorkspaceRule {
        workspace: WorkspaceId,
        monitor: &'a str,
        default: bool,
    },
}

impl Request<'_> {
    /// The hyprctl request name this command is sent with.
    fn kind(&self) -> &'static str {
        match self {
            Request::WorkspaceRule { .. } => "eval",
            _ => "dispatch",
        }
    }

    /// The Lua text of this command.
    pub fn lua(&self) -> String {
        let workspace = |id: &WorkspaceId| lua_string(&id.to_string());
        let window = |address: &Address| lua_string(&format!("address:{address}"));

        match self {
            Request::FocusWorkspace(id) => {
                format!("hl.dsp.focus({{ workspace = {} }})", workspace(id))
            }
            Request::MoveWindowSilent {
                window: address,
                workspace: id,
            } => format!(
                "hl.dsp.window.move({{ window = {}, workspace = {}, follow = false }})",
                window(address),
                workspace(id)
            ),
            Request::MoveWindow {
                window: address,
                workspace: id,
            } => format!(
                "hl.dsp.window.move({{ window = {}, workspace = {} }})",
                window(address),
                workspace(id)
            ),
            Request::MoveActiveWindow(id) => {
                format!("hl.dsp.window.move({{ workspace = {} }})", workspace(id))
            }
            Request::MoveWorkspaceToMonitor {
                workspace: id,
                monitor,
            } => format!(
                "hl.dsp.workspace.move({{ workspace = {}, monitor = {} }})",
                workspace(id),
                lua_string(monitor)
            ),
            Request::FocusWindow(address) => {
                format!("hl.dsp.focus({{ window = {} }})", window(address))
            }
            Request::WorkspaceRule {
                workspace: id,
                monitor,
                default,
            } => format!(
                "hl.workspace_rule({{ workspace = {}, monitor = {}, persistent = true, default = {default} }})",
                workspace(id),
                lua_string(monitor)
            ),
        }
    }

    /// The full request text: the request name followed by the Lua text.
    pub fn command(&self) -> String {
        format!("{} {}", self.kind(), self.lua())
    }

    /// Send this command to Hyprland. Any answer other than `ok` is an error
    /// that carries the request and the answer.
    pub async fn send(&self) -> Result<()> {
        let request = self.command();
        let answer = exchange("", &request).await?;

        if answer == "ok" {
            Ok(())
        } else {
            Err(Error::HyprlandRequest { request, answer })
        }
    }
}

/// Send one request to Hyprland's command socket and return its answer.
/// `flags` are hyprctl's one-letter flags, `j` for an answer in JSON.
pub async fn exchange(flags: &str, request: &str) -> Result<String> {
    let path = socket_path_from(
        std::env::var_os("XDG_RUNTIME_DIR"),
        std::env::var_os("UID"),
        std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE"),
    )?;

    let mut stream = connect(path, CONNECT_WAIT).await?;
    // The slash separates the flags from the request.
    stream
        .write_all(format!("{flags}/{request}").as_bytes())
        .await?;
    let mut answer = Vec::new();
    stream.read_to_end(&mut answer).await?;
    Ok(String::from_utf8_lossy(&answer).into_owned())
}

/// Connect to the socket at `path`, waiting up to `wait` for room in its
/// queue. The connect blocks in the kernel with `wait` as the socket's send
/// timeout, on a thread of the runtime's blocking pool, and the kernel wakes it
/// as soon as the listener accepts a queued connection.
async fn connect(path: PathBuf, wait: Duration) -> Result<UnixStream> {
    let stream = tokio::task::spawn_blocking(move || connect_blocking(&path, wait))
        .await
        .map_err(io::Error::other)??;
    stream.set_nonblocking(true)?;
    Ok(UnixStream::from_std(stream)?)
}

fn connect_blocking(path: &Path, wait: Duration) -> Result<std::os::unix::net::UnixStream> {
    let socket = Socket::new(Domain::UNIX, Type::STREAM, None)?;
    socket.set_write_timeout(Some(wait))?;
    match socket.connect(&SockAddr::unix(path)?) {
        Ok(()) => Ok(OwnedFd::from(socket).into()),
        // A blocking connect whose send timeout runs out reports EAGAIN.
        Err(e) if e.kind() == io::ErrorKind::WouldBlock => Err(Error::HyprlandQueueFull(wait)),
        Err(e) => Err(e.into()),
    }
}

/// Quote a string as a Lua string literal.
pub fn lua_string(value: &str) -> String {
    let mut quoted = String::with_capacity(value.len() + 2);
    quoted.push('"');
    for c in value.chars() {
        match c {
            '"' => quoted.push_str("\\\""),
            '\\' => quoted.push_str("\\\\"),
            '\n' => quoted.push_str("\\n"),
            '\r' => quoted.push_str("\\r"),
            '\t' => quoted.push_str("\\t"),
            // Lua reads up to three decimal digits after a backslash as a byte.
            c if c.is_ascii_control() => {
                let _ = write!(quoted, "\\{:03}", c as u32);
            }
            c => quoted.push(c),
        }
    }
    quoted.push('"');
    quoted
}

/// Locate Hyprland's command socket: the directory named by `XDG_RUNTIME_DIR`,
/// else `/run/user/<UID>`, then `hypr/<instance signature>/.socket.sock`.
fn socket_path_from(
    runtime_dir: Option<OsString>,
    uid: Option<OsString>,
    signature: Option<OsString>,
) -> Result<PathBuf> {
    let mut path = match (runtime_dir, uid) {
        (Some(dir), _) => PathBuf::from(dir),
        (None, Some(uid)) => {
            let mut dir = OsString::from("/run/user/");
            dir.push(uid);
            PathBuf::from(dir)
        }
        (None, None) => return Err(Error::HyprlandSocket("neither XDG_RUNTIME_DIR nor UID is set")),
    };
    let signature =
        signature.ok_or(Error::HyprlandSocket("HYPRLAND_INSTANCE_SIGNATURE is not set"))?;
    path.push("hypr");
    path.push(signature);
    path.push(".socket.sock");
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn address() -> Address {
        Address::new("0x55d0c0ffee00")
    }

    #[test]
    fn focus_workspace() {
        let request = Request::FocusWorkspace(13);
        assert_eq!(request.lua(), r#"hl.dsp.focus({ workspace = "13" })"#);
        assert_eq!(request.command(), r#"dispatch hl.dsp.focus({ workspace = "13" })"#);
    }

    #[test]
    fn move_window_silent() {
        let window = address();
        let request = Request::MoveWindowSilent {
            window: &window,
            workspace: 21,
        };
        assert_eq!(
            request.command(),
            r#"dispatch hl.dsp.window.move({ window = "address:0x55d0c0ffee00", workspace = "21", follow = false })"#
        );
    }

    #[test]
    fn move_window() {
        let window = address();
        let request = Request::MoveWindow {
            window: &window,
            workspace: 5,
        };
        assert_eq!(
            request.command(),
            r#"dispatch hl.dsp.window.move({ window = "address:0x55d0c0ffee00", workspace = "5" })"#
        );
    }

    #[test]
    fn move_active_window() {
        let request = Request::MoveActiveWindow(4);
        assert_eq!(
            request.command(),
            r#"dispatch hl.dsp.window.move({ workspace = "4" })"#
        );
    }

    #[test]
    fn move_workspace_to_monitor() {
        let request = Request::MoveWorkspaceToMonitor {
            workspace: 14,
            monitor: "DP-1",
        };
        assert_eq!(
            request.command(),
            r#"dispatch hl.dsp.workspace.move({ workspace = "14", monitor = "DP-1" })"#
        );
    }

    #[test]
    fn focus_window() {
        let window = address();
        let request = Request::FocusWindow(&window);
        assert_eq!(
            request.command(),
            r#"dispatch hl.dsp.focus({ window = "address:0x55d0c0ffee00" })"#
        );
    }

    #[test]
    fn workspace_rule() {
        let default = Request::WorkspaceRule {
            workspace: 1,
            monitor: "eDP-1",
            default: true,
        };
        assert_eq!(
            default.command(),
            r#"eval hl.workspace_rule({ workspace = "1", monitor = "eDP-1", persistent = true, default = true })"#
        );
        let other = Request::WorkspaceRule {
            workspace: 12,
            monitor: "DP-2",
            default: false,
        };
        assert_eq!(
            other.command(),
            r#"eval hl.workspace_rule({ workspace = "12", monitor = "DP-2", persistent = true, default = false })"#
        );
    }

    #[test]
    fn string_values_are_quoted() {
        let request = Request::MoveWorkspaceToMonitor {
            workspace: 3,
            monitor: "a\"b\\c\nd",
        };
        assert_eq!(
            request.command(),
            r#"dispatch hl.dsp.workspace.move({ workspace = "3", monitor = "a\"b\\c\nd" })"#
        );
    }

    #[test]
    fn lua_string_escapes() {
        assert_eq!(lua_string(""), r#""""#);
        assert_eq!(lua_string("plain"), r#""plain""#);
        assert_eq!(lua_string("q\"b\\n\nr\rt\t"), r#""q\"b\\n\nr\rt\t""#);
        assert_eq!(lua_string("\u{0}\u{1b}\u{7f}"), r#""\000\027\127""#);
        assert_eq!(lua_string("…"), "\"…\"");
    }

    #[test]
    fn socket_path_prefers_runtime_dir() {
        let path = socket_path_from(
            Some("/tmp/runtime".into()),
            Some("1000".into()),
            Some("sig".into()),
        )
        .unwrap();
        assert_eq!(path, PathBuf::from("/tmp/runtime/hypr/sig/.socket.sock"));
    }

    #[test]
    fn socket_path_falls_back_to_uid() {
        let path = socket_path_from(None, Some("1000".into()), Some("sig".into())).unwrap();
        assert_eq!(path, PathBuf::from("/run/user/1000/hypr/sig/.socket.sock"));
    }

    #[test]
    fn socket_path_needs_a_directory_and_a_signature() {
        assert!(socket_path_from(None, None, Some("sig".into())).is_err());
        assert!(socket_path_from(Some("/tmp/runtime".into()), None, None).is_err());
    }

    /// A listening socket whose queue is full: it queues one connection and
    /// already holds one. Removes its socket file when dropped.
    struct FullListener {
        path: PathBuf,
        listener: std::os::unix::net::UnixListener,
        _queued: Socket,
    }

    impl FullListener {
        async fn new(name: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "hypr-workspaced-{}-{name}.sock",
                std::process::id()
            ));
            let _ = std::fs::remove_file(&path);
            let socket = Socket::new(Domain::UNIX, Type::STREAM, None).unwrap();
            socket.bind(&SockAddr::unix(&path).unwrap()).unwrap();
            // Linux queues one connection more than the backlog.
            socket.listen(0).unwrap();
            let listener = std::os::unix::net::UnixListener::from(OwnedFd::from(socket));

            let queued = Socket::new(Domain::UNIX, Type::STREAM, None).unwrap();
            queued.connect(&SockAddr::unix(&path).unwrap()).unwrap();

            let refused = UnixStream::connect(&path).await.unwrap_err();
            assert_eq!(
                refused.kind(),
                io::ErrorKind::WouldBlock,
                "the queue is not full"
            );

            Self {
                path,
                listener,
                _queued: queued,
            }
        }
    }

    impl Drop for FullListener {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.path);
        }
    }

    #[tokio::test]
    async fn connect_waits_for_room_in_the_queue() {
        let full = FullListener::new("waits").await;
        let connecting = tokio::spawn(connect(full.path.clone(), Duration::from_secs(5)));

        tokio::time::sleep(Duration::from_millis(300)).await;
        assert!(!connecting.is_finished(), "the connect did not wait");

        let _accepted = full.listener.accept().unwrap();
        let connected = tokio::time::timeout(Duration::from_secs(2), connecting)
            .await
            .expect("the connect did not complete after the listener accepted")
            .unwrap();
        assert!(connected.is_ok(), "{connected:?}");
    }

    #[tokio::test]
    async fn connect_gives_up_after_the_wait() {
        let full = FullListener::new("gives-up").await;
        let wait = Duration::from_millis(500);

        let started = std::time::Instant::now();
        let result = connect(full.path.clone(), wait).await;
        let waited = started.elapsed();

        assert!(
            matches!(result, Err(Error::HyprlandQueueFull(w)) if w == wait),
            "{result:?}"
        );
        assert!(waited >= wait * 9 / 10, "gave up after {waited:?}");
    }
}

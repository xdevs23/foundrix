//! A headless Hyprland 0.57 that a live test starts for itself, with a
//! runtime directory of its own, so no test reaches the Hyprland of a
//! desktop session.

use std::fs::{self, Permissions};
use std::future::Future;
use std::os::unix::fs::PermissionsExt as _;
use std::panic;
use std::process::Stdio;

use hyproxide::Instance;
use tokio::net::UnixDatagram;
use tokio::process::Child;

use crate::support::TempDirectory;

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
pub async fn with_hyprland<F, T>(test: F)
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

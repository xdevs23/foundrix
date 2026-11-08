//! The systemd manager of the user, on the session bus of D-Bus
//! (<https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.systemd1.html>,
//! checked 2026-11-08).

use serde::Serialize;
use zbus::zvariant::Type;
use zbus::{Connection, OwnedObjectPath};

/// How a new job of a unit treats a job of it that waits.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Type)]
#[serde(rename_all = "kebab-case")]
#[zvariant(signature = "s", crate = "zbus::zvariant")]
pub enum JobMode {
    /// The new job replaces it.
    Replace,
}

#[zbus::proxy(
    default_service = "org.freedesktop.systemd1",
    default_path = "/org/freedesktop/systemd1",
    interface = "org.freedesktop.systemd1.Manager"
)]
pub trait Manager {
    /// Restart a unit, or start it when it does not run, and return its
    /// job.
    fn restart_unit(&self, name: &str, mode: JobMode) -> zbus::Result<OwnedObjectPath>;
}

/// Restart a user service, or start it when it does not run.
///
/// # Errors
///
/// When the session bus or the manager cannot be reached, or the restart
/// fails.
pub async fn restart(service: &str) -> zbus::Result<()> {
    let manager = ManagerProxy::new(&Connection::session().await?).await?;
    let _job: OwnedObjectPath = manager.restart_unit(service, JobMode::Replace).await?;
    Ok(())
}

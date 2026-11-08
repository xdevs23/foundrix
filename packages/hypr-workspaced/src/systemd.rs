//! The systemd manager of the user, on the session bus of D-Bus
//! (<https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.systemd1.html>,
//! checked 2026-11-08).

use serde::{Deserialize, Serialize};
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

/// How a job of a unit ended, with the results the documentation of the
/// manager lists.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Type)]
#[serde(rename_all = "lowercase")]
#[zvariant(signature = "s", crate = "zbus::zvariant")]
pub enum JobResult {
    Done,
    Canceled,
    Timeout,
    Failed,
    Dependency,
    Skipped,
    /// A result the documentation leaves out, which systemd also sends.
    #[serde(other)]
    Unknown,
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

    /// Start a unit, and return its job.
    fn start_unit(&self, name: &str, mode: JobMode) -> zbus::Result<OwnedObjectPath>;

    /// The object of a loaded unit.
    fn get_unit(&self, name: &str) -> zbus::Result<OwnedObjectPath>;

    /// Ask the manager to send its signals, such as `JobRemoved`, to this
    /// client.
    fn subscribe(&self) -> zbus::Result<()>;

    /// A job finished.
    #[zbus(signal)]
    fn job_removed(
        &self,
        id: u32,
        job: OwnedObjectPath,
        unit: String,
        result: JobResult,
    ) -> zbus::Result<()>;
}

#[zbus::proxy(
    default_service = "org.freedesktop.systemd1",
    interface = "org.freedesktop.systemd1.Unit"
)]
pub trait Unit {
    /// The id systemd gives each run of the unit.
    #[zbus(property, name = "InvocationID")]
    fn invocation_id(&self) -> zbus::Result<Vec<u8>>;
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

#[cfg(test)]
mod tests {
    use super::*;

    fn read(result: &str) -> JobResult {
        serde_json::from_value(serde_json::Value::from(result)).unwrap()
    }

    #[test]
    fn job_results_read_their_spelling_and_others_as_unknown() {
        assert_eq!(read("done"), JobResult::Done);
        assert_eq!(read("dependency"), JobResult::Dependency);
        assert_eq!(read("invalid"), JobResult::Unknown);
    }
}

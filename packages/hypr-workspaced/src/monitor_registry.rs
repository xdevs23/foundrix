use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use hyproxide::query::Monitor;
use tracing::info;

use crate::error::{Error, Result};

/// What the registry knows each of `monitors` by: its description, which
/// contains the serial number, or its name when it has no description, as a
/// headless output has none. A description that several of the monitors
/// have, such as that of two panels of one model without a serial number,
/// also gets the name of each, so every monitor has a slot of its own.
pub fn registry_keys(monitors: &[Monitor]) -> Vec<String> {
    fn key(monitor: &Monitor) -> &str {
        if monitor.description.is_empty() {
            &monitor.name
        } else {
            &monitor.description
        }
    }
    monitors
        .iter()
        .map(|monitor| {
            let alike = monitors.iter().filter(|other| key(other) == key(monitor));
            if alike.count() > 1 {
                format!("{} ({})", key(monitor), monitor.name)
            } else {
                key(monitor).to_owned()
            }
        })
        .collect()
}

/// Persistent registry of monitor keys ([`registry_keys`]) to slot indices.
/// Stored as one key per line; the line number (0-indexed) is the slot.
#[derive(Default)]
pub struct MonitorRegistry {
    entries: Vec<String>,
}

impl MonitorRegistry {
    /// The file of the registry, in the state directory of the XDG Base
    /// Directory Specification, which ignores a variable that is unset or
    /// not an absolute path
    /// (<https://specifications.freedesktop.org/basedir-spec/0.8/>, checked
    /// 2026-11-08).
    pub fn path() -> Result<PathBuf> {
        let absolute = |variable| {
            env::var_os(variable)
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
        };
        let state = absolute("XDG_STATE_HOME")
            .or_else(|| absolute("HOME").map(|home| home.join(".local/state")))
            .ok_or(Error::NoStateDirectory)?;
        Ok(state.join("hypr-workspaced").join("monitors"))
    }

    /// Read the registry at `path`. Before the first start of the daemon it
    /// does not exist, and no monitor has a slot yet.
    pub fn load(path: &Path) -> Result<Self> {
        match fs::read_to_string(path) {
            Ok(content) => Ok(Self {
                entries: content
                    .lines()
                    .filter(|l| !l.is_empty())
                    .map(String::from)
                    .collect(),
            }),
            Err(missing) if missing.kind() == io::ErrorKind::NotFound => Ok(Self::default()),
            Err(source) => Err(Error::ReadRegistry {
                path: path.to_owned(),
                source,
            }),
        }
    }

    /// Write the registry to `path`. It goes into a file next to it first,
    /// which then replaces the registry, so a crash leaves either the old or
    /// the new registry, never a part of one.
    pub fn save(&self, path: &Path) -> Result<()> {
        let written = path.with_extension("new");
        let save = || {
            if let Some(directory) = path.parent() {
                fs::create_dir_all(directory)?;
            }
            fs::write(&written, self.entries.join("\n") + "\n")?;
            fs::rename(&written, path)
        };
        save().map_err(|source| Error::WriteRegistry {
            path: path.to_owned(),
            source,
        })
    }

    pub fn slot_for(&self, key: &str) -> Option<usize> {
        self.entries.iter().position(|d| d == key)
    }

    /// Register monitors by their keys and return whether the registry was
    /// modified. On the first run, the monitors get slots in the order
    /// Hyprland lists them. New monitors are appended and get the next
    /// available slot.
    pub fn register<'a>(&mut self, keys: impl IntoIterator<Item = &'a str>) -> bool {
        let mut modified = false;

        if self.entries.is_empty() {
            self.entries.extend(keys.into_iter().map(String::from));
            modified = !self.entries.is_empty();
        } else {
            for key in keys {
                if self.slot_for(key).is_none() {
                    info!("New monitor: {key}, slot {}", self.entries.len());
                    self.entries.push(key.to_owned());
                    modified = true;
                }
            }
        }

        modified
    }
}

#[cfg(test)]
mod tests {
    use hyproxide_testing::TempDirectory;

    use super::*;
    use crate::recorded;

    #[test]
    fn the_registry_keeps_its_slots_in_its_file() {
        let directory = TempDirectory::create();
        let path = directory.path().join("hypr-workspaced").join("monitors");
        let mut registry = MonitorRegistry::load(&path).unwrap();
        assert!(registry.register(["eDP-1 panel", "HEADLESS-2"]));
        registry.save(&path).unwrap();

        let loaded = MonitorRegistry::load(&path).unwrap();
        assert_eq!(loaded.slot_for("eDP-1 panel"), Some(0));
        assert_eq!(loaded.slot_for("HEADLESS-2"), Some(1));
        assert_eq!(
            fs::read_to_string(&path).unwrap(),
            "eDP-1 panel\nHEADLESS-2\n"
        );
    }

    #[test]
    fn a_registry_that_does_not_read_is_an_error() {
        // A directory where the file belongs.
        let directory = TempDirectory::create();
        let loaded = MonitorRegistry::load(directory.path());
        assert!(
            matches!(&loaded, Err(Error::ReadRegistry { path, .. }) if path == directory.path()),
            "{:?}",
            loaded.map(|registry| registry.entries)
        );
    }

    #[test]
    fn registry_gives_each_key_one_slot() {
        let mut registry = MonitorRegistry::default();
        assert!(registry.register(["eDP-1 panel", "HEADLESS-2"]));
        assert!(!registry.register(["HEADLESS-2", "eDP-1 panel"]));
        assert!(registry.register(["HEADLESS-3", "eDP-1 panel"]));
        assert_eq!(registry.slot_for("eDP-1 panel"), Some(0));
        assert_eq!(registry.slot_for("HEADLESS-2"), Some(1));
        assert_eq!(registry.slot_for("HEADLESS-3"), Some(2));
    }

    #[test]
    fn monitors_with_one_description_get_a_slot_each() {
        let mut monitors = recorded::monitors();
        for monitor in &mut monitors {
            "Dell Inc. DELL U2720Q".clone_into(&mut monitor.description);
        }
        let keys = registry_keys(&monitors);
        assert_eq!(
            keys,
            [
                "Dell Inc. DELL U2720Q (Virtual-1)",
                "Dell Inc. DELL U2720Q (HYPR-WORKSPACED-1)"
            ]
        );
        let mut registry = MonitorRegistry::default();
        assert!(registry.register(keys.iter().map(String::as_str)));
        assert_eq!(registry.slot_for(&keys[0]), Some(0));
        assert_eq!(registry.slot_for(&keys[1]), Some(1));

        assert_eq!(registry_keys(&monitors[1..]), ["Dell Inc. DELL U2720Q"]);
    }
}

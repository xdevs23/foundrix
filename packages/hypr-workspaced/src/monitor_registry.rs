use std::path::PathBuf;

use hyproxide::query::Monitor;
use tracing::{info, warn};

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
    fn path() -> PathBuf {
        let state_dir = std::env::var("XDG_STATE_HOME").map_or_else(
            |_| {
                let home = std::env::var("HOME").expect("HOME not set");
                PathBuf::from(home).join(".local/state")
            },
            PathBuf::from,
        );
        state_dir.join("hypr-workspaced").join("monitors")
    }

    pub fn load() -> Self {
        let entries = match std::fs::read_to_string(Self::path()) {
            Ok(content) => content
                .lines()
                .filter(|l| !l.is_empty())
                .map(String::from)
                .collect(),
            Err(_) => Vec::new(),
        };
        Self { entries }
    }

    pub fn save(&self) {
        let path = Self::path();
        if let Some(parent) = path.parent()
            && let Err(e) = std::fs::create_dir_all(parent)
        {
            warn!("Failed to create registry directory: {e}");
            return;
        }
        if let Err(e) = std::fs::write(&path, self.entries.join("\n") + "\n") {
            warn!("Failed to save monitor registry: {e}");
        }
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
    use super::*;
    use crate::recorded;

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

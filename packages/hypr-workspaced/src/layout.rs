use std::collections::HashMap;

use hyproxide::monitor::MonitorId;
use hyproxide::query::Monitor;
use hyproxide::workspace::WorkspaceId;
use tracing::{debug, warn};

use crate::error::{Error, Result};
use crate::monitor_registry::{MonitorRegistry, registry_keys};
use crate::virtual_workspace::{MonitorSlot, VirtualWorkspace};

/// Mapping from Hyprland monitor IDs to stable monitor slots.
pub struct MonitorLayout {
    slots: HashMap<MonitorId, MonitorSlot>,
}

impl MonitorLayout {
    pub fn new() -> Self {
        Self {
            slots: HashMap::new(),
        }
    }

    /// Build a layout using the persistent monitor registry.
    /// Each physical monitor (identified by description/serial) gets a permanent
    /// slot that survives disconnects and restarts.
    pub fn assign(monitors: &[Monitor]) -> Result<Self> {
        let keys = registry_keys(monitors);
        let path = MonitorRegistry::path()?;
        let mut registry = MonitorRegistry::load(&path)?;
        if registry.register(keys.iter().map(String::as_str)) {
            registry.save(&path)?;
        }
        Ok(Self::from_registry(&registry, monitors, &keys))
    }

    /// The slots `registry` has for `monitors`, which it knows by `keys`.
    fn from_registry(registry: &MonitorRegistry, monitors: &[Monitor], keys: &[String]) -> Self {
        let mut slots = HashMap::new();
        for (monitor, key) in monitors.iter().zip(keys) {
            let Some(index) = registry.slot_for(key) else {
                continue;
            };
            let Ok(index) = u8::try_from(index) else {
                warn!(
                    "No slot left for {} ({})",
                    monitor.name, monitor.description
                );
                continue;
            };
            let slot = MonitorSlot::new(index);
            debug!(
                "Slot {} -> {} (id={}, {})",
                slot.index(),
                monitor.name,
                monitor.id,
                monitor.description
            );
            let _earlier_slot_of_a_monitor_listed_twice = slots.insert(monitor.id, slot);
        }

        Self { slots }
    }

    /// The slot the layout gave the monitor with this Hyprland id, `None`
    /// for a monitor connected after the layout was assigned.
    pub fn slot_for(&self, monitor_id: MonitorId) -> Option<MonitorSlot> {
        self.slots.get(&monitor_id).copied()
    }

    /// The slot of a monitor that the daemon acts on.
    pub fn slot_of(&self, monitor: &Monitor) -> Result<MonitorSlot> {
        self.slot_for(monitor.id)
            .ok_or_else(|| Error::NoSlot(monitor.name.clone()))
    }

    /// Build a reverse mapping: slot → monitor name.
    pub fn slot_to_monitor_name<'a>(
        &self,
        monitors: &'a [Monitor],
    ) -> HashMap<MonitorSlot, &'a str> {
        monitors
            .iter()
            .filter_map(|m| Some((self.slot_for(m.id)?, m.name.as_str())))
            .collect()
    }

    /// Iterate all assigned slots (useful for orphan cleanup).
    pub fn all_slots(&self) -> impl Iterator<Item = MonitorSlot> + '_ {
        let max = self.slots.values().map(|s| s.index()).max().unwrap_or(0);
        (0..=max).map(MonitorSlot::new)
    }
}

/// Check whether a Hyprland workspace ID belongs to a valid virtual workspace
/// on an existing monitor slot.
pub fn is_valid_workspace(id: WorkspaceId, num_monitors: usize) -> bool {
    VirtualWorkspace::from_hyprland_id(id).is_some()
        && MonitorSlot::from_hyprland_id(id)
            .is_some_and(|slot| usize::from(slot.index()) < num_monitors)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::recorded;

    #[test]
    fn only_monitors_of_the_layout_have_a_slot() {
        let monitors = recorded::monitors();
        let assigned = &monitors[..1];
        let keys = registry_keys(assigned);
        let mut registry = MonitorRegistry::default();
        assert!(registry.register(keys.iter().map(String::as_str)));
        let layout = MonitorLayout::from_registry(&registry, assigned, &keys);

        assert_eq!(layout.slot_for(monitors[0].id), Some(MonitorSlot::new(0)));
        // The second output, connected after the assignment, has the
        // Hyprland id 1, which is no slot of it.
        assert_eq!(layout.slot_for(monitors[1].id), None);
        let unassigned = layout.slot_of(&monitors[1]);
        assert!(
            matches!(&unassigned, Err(Error::NoSlot(name)) if name == "HYPR-WORKSPACED-1"),
            "{unassigned:?}"
        );
    }
}

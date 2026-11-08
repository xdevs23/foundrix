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
    pub fn assign(monitors: &[Monitor]) -> Self {
        let keys = registry_keys(monitors);
        let mut registry = MonitorRegistry::load();
        if registry.register(keys.iter().map(String::as_str)) {
            registry.save();
        }

        let mut slots = HashMap::new();
        for (monitor, key) in monitors.iter().zip(&keys) {
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

    /// Look up the slot for a Hyprland monitor ID.
    /// Falls back to treating the raw ID as a slot index if no mapping exists,
    /// and to `None` for an ID that is no slot index.
    pub fn slot_for(&self, monitor_id: MonitorId) -> Option<MonitorSlot> {
        self.slots
            .get(&monitor_id)
            .copied()
            .or_else(|| u8::try_from(monitor_id.get()).ok().map(MonitorSlot::new))
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

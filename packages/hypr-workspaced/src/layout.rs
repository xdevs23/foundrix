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

    /// Whether `workspace` is a virtual workspace on a slot of the layout,
    /// so a monitor connected now shows it.
    pub fn has_workspace(&self, workspace: WorkspaceId) -> bool {
        VirtualWorkspace::from_hyprland_id(workspace).is_some()
            && MonitorSlot::from_hyprland_id(workspace)
                .is_some_and(|slot| self.slots.values().any(|&assigned| assigned == slot))
    }

    /// Iterate all assigned slots (useful for orphan cleanup).
    pub fn all_slots(&self) -> impl Iterator<Item = MonitorSlot> + '_ {
        let max = self.slots.values().map(|s| s.index()).max().unwrap_or(0);
        (0..=max).map(MonitorSlot::new)
    }
}

#[cfg(test)]
impl MonitorLayout {
    /// The layout of `monitors` that a fresh registry gives, with the slots
    /// in their order.
    pub fn of_new_monitors(monitors: &[Monitor]) -> Self {
        let keys = registry_keys(monitors);
        let mut registry = MonitorRegistry::default();
        assert!(registry.register(keys.iter().map(String::as_str)));
        Self::from_registry(&registry, monitors, &keys)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::recorded;

    fn id(number: u32) -> WorkspaceId {
        WorkspaceId::try_from(number).unwrap()
    }

    #[test]
    fn only_monitors_of_the_layout_have_a_slot() {
        let monitors = recorded::monitors();
        let layout = MonitorLayout::of_new_monitors(&monitors[..1]);

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

    #[test]
    fn only_slots_of_the_layout_have_workspaces() {
        let monitors = recorded::monitors();
        let both = MonitorLayout::of_new_monitors(&monitors);
        assert!(both.has_workspace(id(3)));
        assert!(both.has_workspace(id(13)));
        // The orphan workspace of slot 1, and workspace 3 of slot 2.
        assert!(!both.has_workspace(id(10)));
        assert!(!both.has_workspace(id(23)));

        let first = MonitorLayout::of_new_monitors(&monitors[..1]);
        assert!(first.has_workspace(id(3)));
        assert!(!first.has_workspace(id(13)));
    }
}

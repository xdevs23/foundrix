use std::num::{NonZeroU8, NonZeroU16};

use hyproxide::workspace::WorkspaceId;

use crate::error::{Error, Result};

/// A user-facing virtual workspace (valid range: 1–9).
///
/// All monitors are synchronised to the same virtual workspace — each monitor
/// shows its own Hyprland workspace that corresponds to this number.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct VirtualWorkspace(NonZeroU8);

impl VirtualWorkspace {
    pub const FIRST: Self = Self(NonZeroU8::MIN);

    pub fn new(n: u8) -> Result<Self> {
        NonZeroU8::new(n)
            .filter(|n| n.get() <= 9)
            .map(Self)
            .ok_or(Error::InvalidVirtualWorkspace(n))
    }

    /// Virtual workspaces 1 to 9.
    pub fn all() -> impl Iterator<Item = Self> {
        (1..=9).filter_map(|n| Self::new(n).ok())
    }

    #[cfg(test)]
    pub fn number(self) -> u8 {
        self.0.get()
    }

    pub fn next(self) -> Self {
        Self(NonZeroU8::MIN.saturating_add(self.0.get() % 9))
    }

    pub fn prev(self) -> Self {
        Self(NonZeroU8::MIN.saturating_add((self.0.get() + 7) % 9))
    }

    /// Compute the Hyprland workspace ID for this virtual workspace on the
    /// given monitor slot: at most 2559, so the sum cannot saturate.
    pub fn hyprland_id(self, slot: MonitorSlot) -> WorkspaceId {
        WorkspaceId::from(NonZeroU16::from(self.0).saturating_add(u16::from(slot.0) * 10))
    }

    /// Extract the virtual workspace from a Hyprland workspace ID.
    /// Returns `None` for orphan IDs (multiples of 10).
    pub fn from_hyprland_id(id: WorkspaceId) -> Option<Self> {
        NonZeroU8::new(u8::try_from(id.get() % 10).ok()?).map(Self)
    }
}

impl std::fmt::Display for VirtualWorkspace {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// A stable index (0, 1, 2, …) assigned to a physical monitor.
///
/// The monitor registry gives each monitor its slot by its description, which
/// contains the serial number, so the same physical monitor always gets the
/// same slot regardless of connector name or Hyprland ID.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct MonitorSlot(u8);

impl MonitorSlot {
    pub fn new(index: u8) -> Self {
        Self(index)
    }

    pub fn index(self) -> u8 {
        self.0
    }

    /// The orphan workspace ID for this slot (10, 20, …). Slot 0 has none:
    /// Hyprland has no workspace 0. These workspaces are never valid —
    /// clients on them need rescuing.
    pub fn orphan_workspace_id(self) -> Option<WorkspaceId> {
        NonZeroU16::new(u16::from(self.0) * 10).map(WorkspaceId::from)
    }

    /// Extract the monitor slot from a Hyprland workspace ID, `None` for IDs
    /// past the last slot.
    pub fn from_hyprland_id(id: WorkspaceId) -> Option<Self> {
        u8::try_from(id.get() / 10).ok().map(Self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn id(number: u32) -> WorkspaceId {
        WorkspaceId::try_from(number).unwrap()
    }

    #[test]
    fn virtual_workspace_validation() {
        assert!(VirtualWorkspace::new(0).is_err());
        assert!(VirtualWorkspace::new(10).is_err());
        for n in 1..=9 {
            assert_eq!(VirtualWorkspace::new(n).unwrap().number(), n);
        }
        let all: Vec<_> = VirtualWorkspace::all()
            .map(VirtualWorkspace::number)
            .collect();
        assert_eq!(all, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    }

    #[test]
    fn virtual_workspace_navigation() {
        let ws = VirtualWorkspace::new(1).unwrap();
        assert_eq!(ws.next().number(), 2);
        assert_eq!(ws.prev().number(), 9);

        let ws = VirtualWorkspace::new(9).unwrap();
        assert_eq!(ws.next().number(), 1);
        assert_eq!(ws.prev().number(), 8);

        let ws = VirtualWorkspace::new(5).unwrap();
        assert_eq!(ws.next().number(), 6);
        assert_eq!(ws.prev().number(), 4);
    }

    #[test]
    fn hyprland_id_mapping() {
        let slot0 = MonitorSlot::new(0);
        let slot1 = MonitorSlot::new(1);
        let slot2 = MonitorSlot::new(2);
        let last = MonitorSlot::new(u8::MAX);
        let vws = |n| VirtualWorkspace::new(n).unwrap();

        // slot 0 -> workspaces 1-9
        assert_eq!(vws(1).hyprland_id(slot0), id(1));
        assert_eq!(vws(9).hyprland_id(slot0), id(9));
        // slot 1 -> workspaces 11-19
        assert_eq!(vws(1).hyprland_id(slot1), id(11));
        assert_eq!(vws(4).hyprland_id(slot1), id(14));
        // slot 2 -> workspaces 21-29
        assert_eq!(vws(1).hyprland_id(slot2), id(21));
        assert_eq!(vws(9).hyprland_id(last), id(2559));
    }

    #[test]
    fn from_hyprland_id() {
        // Normal workspace IDs
        assert_eq!(
            VirtualWorkspace::from_hyprland_id(id(1)).unwrap().number(),
            1
        );
        assert_eq!(
            VirtualWorkspace::from_hyprland_id(id(9)).unwrap().number(),
            9
        );
        assert_eq!(
            VirtualWorkspace::from_hyprland_id(id(14)).unwrap().number(),
            4
        );
        assert_eq!(
            VirtualWorkspace::from_hyprland_id(id(23)).unwrap().number(),
            3
        );

        // Orphan IDs
        assert!(VirtualWorkspace::from_hyprland_id(id(10)).is_none());
        assert!(VirtualWorkspace::from_hyprland_id(id(20)).is_none());
    }

    #[test]
    fn monitor_slot_from_hyprland_id() {
        let slot = |n| MonitorSlot::from_hyprland_id(id(n)).map(MonitorSlot::index);
        assert_eq!(slot(1), Some(0));
        assert_eq!(slot(9), Some(0));
        assert_eq!(slot(11), Some(1));
        assert_eq!(slot(14), Some(1));
        assert_eq!(slot(21), Some(2));
        assert_eq!(slot(2559), Some(255));
        assert_eq!(slot(2560), None);
    }

    #[test]
    fn orphan_workspace_ids() {
        assert_eq!(MonitorSlot::new(0).orphan_workspace_id(), None);
        assert_eq!(MonitorSlot::new(1).orphan_workspace_id(), Some(id(10)));
        assert_eq!(MonitorSlot::new(2).orphan_workspace_id(), Some(id(20)));
    }
}

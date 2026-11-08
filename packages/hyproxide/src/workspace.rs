//! How Hyprland identifies workspaces.
//!
//! Since Hyprland 0.57 only a numbered workspace has an id. A named workspace
//! and a special one are known by their address alone.

use std::fmt::{self, Display, Formatter};
use std::num::NonZeroU32;

use crate::error::NextStep;

/// The number of a numbered workspace, from 1 to 2147483647: the numbers
/// Hyprland reads in a workspace selector
/// (<https://github.com/hyprwm/Hyprland/blob/v0.57.1/src/state/workspace/Resolver.cpp>,
/// checked 2026-11-08).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct WorkspaceId(NonZeroU32);

impl WorkspaceId {
    const LAST: u32 = i32::MAX.unsigned_abs();

    #[must_use]
    pub fn get(self) -> u32 {
        self.0.get()
    }
}

impl TryFrom<u32> for WorkspaceId {
    type Error = InvalidWorkspaceId;

    fn try_from(number: u32) -> Result<Self, Self::Error> {
        NonZeroU32::new(number)
            .filter(|number| number.get() <= Self::LAST)
            .map(Self)
            .ok_or(InvalidWorkspaceId(number))
    }
}

impl Display for WorkspaceId {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// A number that is not a workspace number.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("{number} is not a workspace number. {next}", number = .0, next = NextStep::UseAWorkspaceNumber)]
pub struct InvalidWorkspaceId(pub u32);

/// Whether a workspace is a normal or a special one.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceKind {
    Normal,
    Special,
    /// There is no workspace: a disabled monitor has none, and a monitor
    /// without an open special workspace has no special one.
    None,
}

/// A workspace named inside another answer, such as the active workspace of
/// a monitor or the workspace of a window.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceRef {
    /// Only numbered workspaces have one.
    pub id: Option<WorkspaceId>,
    pub kind: WorkspaceKind,
    /// The name Hyprland addresses the workspace by: the number of a
    /// numbered workspace, the name of a named one, `special:<name>` for a
    /// special one.
    pub address: String,
    /// The name shown for the workspace, which a rename changes.
    pub name: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspace_numbers_run_from_1_to_the_largest_i32() {
        assert_eq!(WorkspaceId::try_from(1).unwrap().get(), 1);
        assert_eq!(
            WorkspaceId::try_from(2_147_483_647).unwrap().get(),
            2_147_483_647
        );
        for number in [0, 2_147_483_648, u32::MAX] {
            assert_eq!(
                WorkspaceId::try_from(number),
                Err(InvalidWorkspaceId(number))
            );
        }
    }
}

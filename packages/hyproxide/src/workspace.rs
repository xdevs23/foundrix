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

/// The name of a named workspace: not empty and not a number, which Hyprland
/// would read as the id of a numbered workspace.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct WorkspaceName(String);

impl TryFrom<String> for WorkspaceName {
    type Error = NotAWorkspaceName;

    fn try_from(name: String) -> Result<Self, Self::Error> {
        if name.is_empty() || name.bytes().all(|byte| byte.is_ascii_digit()) {
            Err(NotAWorkspaceName(name))
        } else {
            Ok(Self(name))
        }
    }
}

impl TryFrom<&str> for WorkspaceName {
    type Error = NotAWorkspaceName;

    fn try_from(name: &str) -> Result<Self, Self::Error> {
        Self::try_from(name.to_owned())
    }
}

impl Display for WorkspaceName {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// Text that cannot name a named workspace.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{name:?} is not a workspace name. {next}", name = .0, next = NextStep::UseAWorkspaceName)]
pub struct NotAWorkspaceName(pub String);

/// Whether a workspace is a normal or a special one.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WorkspaceKind {
    Normal,
    Special,
    /// There is no workspace: a disabled monitor has none, and a monitor
    /// without an open special workspace has no special one.
    None,
}

/// The prefix of the address of every special workspace, and of the selector
/// of one.
pub(crate) const SPECIAL: &str = "special:";

/// The address Hyprland knows a workspace by, which it displays as Hyprland
/// writes it: the number of a numbered workspace, the name of a named one,
/// `special:<name>` for a special one, and nothing for no workspace.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WorkspaceAddress {
    Numbered(WorkspaceId),
    Named(WorkspaceName),
    /// A special workspace, by the part of its address after `special:`.
    Special(String),
    /// There is no workspace, see [`WorkspaceKind::None`].
    None,
}

impl WorkspaceAddress {
    #[must_use]
    pub fn kind(&self) -> WorkspaceKind {
        match self {
            Self::Numbered(_) | Self::Named(_) => WorkspaceKind::Normal,
            Self::Special(_) => WorkspaceKind::Special,
            Self::None => WorkspaceKind::None,
        }
    }

    /// Only numbered workspaces have one.
    #[must_use]
    pub fn id(&self) -> Option<WorkspaceId> {
        match self {
            Self::Numbered(id) => Some(*id),
            Self::Named(_) | Self::Special(_) | Self::None => None,
        }
    }
}

impl Display for WorkspaceAddress {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Self::Numbered(id) => write!(f, "{id}"),
            Self::Named(name) => write!(f, "{name}"),
            Self::Special(name) => write!(f, "{SPECIAL}{name}"),
            Self::None => Ok(()),
        }
    }
}

/// A workspace named inside an answer or an event, such as the active
/// workspace of a monitor or the workspace of a window, with the name shown
/// for it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceRef {
    pub address: WorkspaceAddress,
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

    #[test]
    fn workspace_names_are_not_numbers() {
        assert!(WorkspaceName::try_from("web 2").is_ok());
        assert!(WorkspaceName::try_from("2web").is_ok());
        for name in ["", "2", "0042"] {
            assert_eq!(
                WorkspaceName::try_from(name),
                Err(NotAWorkspaceName(name.to_owned()))
            );
        }
    }

    #[test]
    fn addresses_are_written_as_hyprland_writes_them() {
        let web = WorkspaceName::try_from("web").unwrap();
        for (address, text, kind, id) in [
            (
                WorkspaceAddress::Numbered(WorkspaceId::try_from(6).unwrap()),
                "6",
                WorkspaceKind::Normal,
                WorkspaceId::try_from(6).ok(),
            ),
            (
                WorkspaceAddress::Named(web),
                "web",
                WorkspaceKind::Normal,
                None,
            ),
            (
                WorkspaceAddress::Special("scratch".into()),
                "special:scratch",
                WorkspaceKind::Special,
                None,
            ),
            (WorkspaceAddress::None, "", WorkspaceKind::None, None),
        ] {
            assert_eq!(address.to_string(), text);
            assert_eq!(address.kind(), kind, "{text:?}");
            assert_eq!(address.id(), id, "{text:?}");
        }
    }
}

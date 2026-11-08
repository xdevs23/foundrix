//! The rule functions of the configuration, which [`apply`] sends.

use std::fmt::{self, Display, Formatter};

use super::WorkspaceSelector;
use crate::error::Result;
use crate::lua::{Call, Table};
use crate::socket::Instance;

/// A call of `hl.workspace_rule`. A rule for a workspace that already has
/// one replaces it. Its Lua text is what it displays as.
///
/// The rule also takes gaps, borders, a layout and more. This builder does
/// not type them: write such a rule as Lua text for `eval`.
#[derive(Debug, Clone, PartialEq)]
#[must_use]
pub struct WorkspaceRule(Table);

pub fn workspace_rule(workspace: impl Into<WorkspaceSelector>) -> WorkspaceRule {
    WorkspaceRule(Table::new().with("workspace", workspace.into()))
}

impl WorkspaceRule {
    /// Bind the workspace to the monitor with this name.
    pub fn monitor(self, name: &str) -> Self {
        Self(self.0.with("monitor", name))
    }

    /// Keep the workspace while it has no windows.
    pub fn persistent(self, persistent: bool) -> Self {
        Self(self.0.with("persistent", persistent))
    }

    /// Show the workspace first on its monitor.
    pub fn default(self, default: bool) -> Self {
        Self(self.0.with("default", default))
    }
}

/// Add a rule to the configuration Hyprland runs.
///
/// # Errors
///
/// Fails like [`eval`](super::eval), which runs the Lua text of the rule.
pub async fn apply(instance: &Instance, rule: &WorkspaceRule) -> Result<()> {
    super::eval(instance, &rule.to_string()).await
}

impl Display for WorkspaceRule {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        let call = Call::new("hl.workspace_rule", vec![self.0.clone().into()]);
        write!(f, "{call}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::workspace::WorkspaceId;

    #[test]
    fn workspace_rules() {
        let thirteen = WorkspaceId::try_from(13).unwrap();
        assert_eq!(
            workspace_rule(thirteen).to_string(),
            r#"hl.workspace_rule({ workspace = "13" })"#
        );
        assert_eq!(
            workspace_rule(thirteen)
                .monitor("DP-1")
                .persistent(true)
                .default(false)
                .to_string(),
            r#"hl.workspace_rule({ workspace = "13", monitor = "DP-1", persistent = true, default = false })"#
        );
    }
}

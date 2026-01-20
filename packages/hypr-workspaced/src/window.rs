use hyprland::data::{Client, FullscreenMode};

/// A pattern for matching windows, using Hyprland's window identifier syntax.
///
/// Supported patterns:
/// - `class:<regex>` - Match window class
/// - `title:<regex>` - Match window title
/// - `pid:<number>` - Match process ID
/// - `address:<hex>` - Match window address
/// - `floating:` - Match floating windows (true/false or 0/1)
/// - `fullscreen:` - Match fullscreen windows (true/false or 0/1)
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WindowPattern {
    Class(String),
    Title(String),
    Pid(i32),
    Address(String),
    Floating(bool),
    Fullscreen(bool),
}

impl WindowPattern {
    pub fn parse(spec: &str) -> Option<Self> {
        let (prefix, value) = spec.split_once(':')?;

        match prefix {
            "class" => Some(WindowPattern::Class(value.to_string())),
            "title" => Some(WindowPattern::Title(value.to_string())),
            "pid" => value.parse().ok().map(WindowPattern::Pid),
            "address" => Some(WindowPattern::Address(value.to_string())),
            "floating" => parse_bool(value).map(WindowPattern::Floating),
            "fullscreen" => parse_bool(value).map(WindowPattern::Fullscreen),
            _ => None,
        }
    }

    pub fn matches(&self, client: &Client) -> bool {
        match self {
            WindowPattern::Class(pattern) => {
                client.class.contains(pattern) || client.initial_class.contains(pattern)
            }
            WindowPattern::Title(pattern) => {
                client.title.contains(pattern) || client.initial_title.contains(pattern)
            }
            WindowPattern::Pid(pid) => client.pid == *pid,
            WindowPattern::Address(addr) => {
                let client_addr = format!("{}", client.address);
                client_addr.contains(addr)
            }
            WindowPattern::Floating(floating) => client.floating == *floating,
            WindowPattern::Fullscreen(fs) => {
                let is_fullscreen = client.fullscreen != FullscreenMode::None;
                is_fullscreen == *fs
            }
        }
    }
}

impl std::fmt::Display for WindowPattern {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WindowPattern::Class(v) => write!(f, "class:{v}"),
            WindowPattern::Title(v) => write!(f, "title:{v}"),
            WindowPattern::Pid(v) => write!(f, "pid:{v}"),
            WindowPattern::Address(v) => write!(f, "address:{v}"),
            WindowPattern::Floating(v) => write!(f, "floating:{v}"),
            WindowPattern::Fullscreen(v) => write!(f, "fullscreen:{v}"),
        }
    }
}

fn parse_bool(s: &str) -> Option<bool> {
    match s {
        "true" | "1" | "yes" => Some(true),
        "false" | "0" | "no" => Some(false),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_patterns() {
        assert_eq!(
            WindowPattern::parse("class:firefox"),
            Some(WindowPattern::Class("firefox".to_string()))
        );
        assert_eq!(
            WindowPattern::parse("title:YouTube"),
            Some(WindowPattern::Title("YouTube".to_string()))
        );
        assert_eq!(WindowPattern::parse("pid:1234"), Some(WindowPattern::Pid(1234)));
        assert_eq!(
            WindowPattern::parse("floating:true"),
            Some(WindowPattern::Floating(true))
        );
        assert_eq!(
            WindowPattern::parse("floating:0"),
            Some(WindowPattern::Floating(false))
        );
        assert_eq!(WindowPattern::parse("invalid"), None);
    }

    #[test]
    fn roundtrip() {
        let pattern = WindowPattern::Class("mattermost".to_string());
        assert_eq!(
            WindowPattern::parse(&pattern.to_string()),
            Some(pattern)
        );
    }
}

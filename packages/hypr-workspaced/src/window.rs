use hyproxide::query::{Client, ClientFlag};
use hyproxide::window::FullscreenState;

/// A pattern for matching windows, using Hyprland's window identifier syntax.
///
/// Supported patterns:
/// - `class:<text>` - Match a substring of the window class
/// - `title:<text>` - Match a substring of the window title
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
            WindowPattern::Address(addr) => client.address.to_string().contains(addr),
            WindowPattern::Floating(floating) => {
                client.flags.contains(ClientFlag::Floating) == *floating
            }
            WindowPattern::Fullscreen(fs) => {
                let is_fullscreen = client.fullscreen != FullscreenState::None;
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
        assert_eq!(
            WindowPattern::parse("pid:1234"),
            Some(WindowPattern::Pid(1234))
        );
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

    /// The `clients` answer of Hyprland 0.57.1 with two outputs and windows
    /// that are tiled, floating, fullscreen, of another class and on a
    /// special workspace, each with a title that says so.
    fn recorded_clients() -> Vec<Client> {
        serde_json::from_str(include_str!(
            "../testdata/hyprland-answers/clients-two-outputs.json"
        ))
        .unwrap()
    }

    /// The titles of the recorded windows that `pattern` matches.
    fn matched(pattern: &str) -> Vec<String> {
        let pattern = WindowPattern::parse(pattern).unwrap();
        recorded_clients()
            .into_iter()
            .filter(|client| pattern.matches(client))
            .map(|client| client.title)
            .collect()
    }

    /// The titles of the recorded windows other than `excluded`.
    fn all_but(excluded: &str) -> Vec<String> {
        recorded_clients()
            .into_iter()
            .map(|client| client.title)
            .filter(|title| title != excluded)
            .collect()
    }

    #[test]
    fn patterns_match_the_windows_they_name() {
        assert_eq!(matched("class:notes"), ["notes on 15"]);
        assert_eq!(matched("class:foo"), all_but("notes on 15"));
        assert_eq!(
            matched("title:on 1"),
            ["tiled on 13", "floating on 13", "notes on 15"]
        );
        assert_eq!(matched("pid:1103"), ["notes on 15"]);
        assert_eq!(matched("address:0x55a52709a730"), ["floating on 13"]);
        assert_eq!(matched("address:55a52709a730"), ["floating on 13"]);
        assert_eq!(matched("floating:true"), ["floating on 13"]);
        assert_eq!(matched("floating:false"), all_but("floating on 13"));
        assert_eq!(matched("fullscreen:true"), ["fullscreen on 3"]);
        assert_eq!(matched("fullscreen:false"), all_but("fullscreen on 3"));
    }

    #[test]
    fn roundtrip() {
        let pattern = WindowPattern::Class("mattermost".to_string());
        assert_eq!(WindowPattern::parse(&pattern.to_string()), Some(pattern));
    }
}

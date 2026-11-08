//! One argument of a plain request.

use std::fmt::{self, Display, Formatter};

use crate::error::NextStep;

/// Text that Hyprland reads as one argument of a plain request, such as an
/// output name or a cursor theme: not empty, without whitespace and without
/// control characters. Hyprland splits plain requests at spaces.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Word(String);

impl Word {
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl TryFrom<String> for Word {
    type Error = NotAWord;

    fn try_from(text: String) -> Result<Self, Self::Error> {
        let splits = text.is_empty() || text.chars().any(|c| c.is_whitespace() || c.is_control());
        if splits {
            Err(NotAWord(text))
        } else {
            Ok(Self(text))
        }
    }
}

impl TryFrom<&str> for Word {
    type Error = NotAWord;

    fn try_from(text: &str) -> Result<Self, Self::Error> {
        Self::try_from(text.to_owned())
    }
}

impl Display for Word {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// Text that Hyprland would not read as one argument.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
#[error("{text:?} is empty or has whitespace or control characters. {next}", text = .0, next = NextStep::UseOneWord)]
pub struct NotAWord(pub String);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_word_has_no_whitespace() {
        assert_eq!(
            Word::try_from("Bibata-Modern").unwrap().as_str(),
            "Bibata-Modern"
        );
        for text in ["", "Bibata Modern", "line\nbreak", "tab\tbed", "bell\u{7}"] {
            assert_eq!(Word::try_from(text), Err(NotAWord(text.to_owned())));
        }
    }
}

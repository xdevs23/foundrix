//! Sets of the boolean fields of an answer.
//!
//! Answers such as a client have many boolean fields side by side. A struct
//! that flattens a [`Flags`] field reads each of them into one value of a
//! flag enum, defined with [`flag_set!`], and fails when the answer lacks one.

use std::fmt::{self, Formatter};
use std::marker::PhantomData;

use serde::Deserialize;
use serde::de::{self, Deserializer, IgnoredAny, MapAccess, Visitor};

/// An enum whose values are the boolean fields of an answer.
pub trait Flag: Copy + PartialEq + 'static {
    const ALL: &'static [Self];

    /// The field of the answer that has this flag.
    fn field(self) -> &'static str;
}

/// Define a [`Flag`] enum, each value with the field it is read from.
macro_rules! flag_set {
    (
        $(#[$meta:meta])*
        pub enum $name:ident {
            $($(#[$value_meta:meta])* $value:ident = $field:literal),* $(,)?
        }
    ) => {
        $(#[$meta])*
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
        pub enum $name {
            $($(#[$value_meta])* $value),*
        }

        impl $crate::query::Flag for $name {
            const ALL: &'static [Self] = &[$(Self::$value),*];

            fn field(self) -> &'static str {
                match self {
                    $(Self::$value => $field),*
                }
            }
        }
    };
}
pub(super) use flag_set;

/// The flags of an answer that are set, in the order of the answer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Flags<F>(Vec<F>);

impl<F: Flag> Flags<F> {
    #[must_use]
    pub fn contains(&self, flag: F) -> bool {
        self.0.contains(&flag)
    }

    pub fn iter(&self) -> impl Iterator<Item = F> + '_ {
        self.0.iter().copied()
    }
}

/// Reads the fields left over by the struct that flattens the set: a field
/// of a flag adds the flag when true, and other fields are skipped.
impl<'de, F: Flag> Deserialize<'de> for Flags<F> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        deserializer.deserialize_map(FlagVisitor(PhantomData))
    }
}

struct FlagVisitor<F>(PhantomData<F>);

impl<'de, F: Flag> Visitor<'de> for FlagVisitor<F> {
    type Value = Flags<F>;

    fn expecting(&self, f: &mut Formatter<'_>) -> fmt::Result {
        f.write_str("boolean fields")
    }

    fn visit_map<A: MapAccess<'de>>(self, mut fields: A) -> Result<Self::Value, A::Error> {
        let mut read = Vec::new();
        let mut set = Vec::new();
        while let Some(name) = fields.next_key::<String>()? {
            match F::ALL.iter().find(|flag| flag.field() == name) {
                Some(&flag) => {
                    read.push(flag);
                    if fields.next_value::<bool>()? {
                        set.push(flag);
                    }
                }
                None => {
                    let IgnoredAny = fields.next_value()?;
                }
            }
        }
        match F::ALL.iter().find(|flag| !read.contains(flag)) {
            Some(missing) => Err(de::Error::missing_field(missing.field())),
            None => Ok(Flags(set)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    flag_set! {
        pub enum TestFlag {
            Mapped = "mapped",
            AcceptsInput = "acceptsInput",
            Hidden = "hidden",
        }
    }

    #[derive(Debug, Deserialize)]
    struct Answer {
        name: String,
        #[serde(flatten)]
        flags: Flags<TestFlag>,
    }

    fn answer(json: &str) -> serde_json::Result<Answer> {
        serde_json::from_str(json)
    }

    #[test]
    fn true_fields_become_flags() {
        let answer = answer(
            r#"{"mapped": true, "name": "a", "hidden": false, "acceptsInput": true, "other": [1]}"#,
        )
        .unwrap();
        assert_eq!(answer.name, "a");
        assert_eq!(
            answer.flags.iter().collect::<Vec<_>>(),
            [TestFlag::Mapped, TestFlag::AcceptsInput]
        );
        assert!(!answer.flags.contains(TestFlag::Hidden));
    }

    #[test]
    fn a_flag_must_be_a_boolean() {
        let answer = answer(r#"{"name": "a", "mapped": 1, "acceptsInput": true, "hidden": false}"#);
        assert!(answer.is_err());
    }

    #[test]
    fn an_answer_without_a_flag_fails() {
        let error = answer(r#"{"name": "a", "mapped": true, "hidden": false}"#).unwrap_err();
        assert!(
            error.to_string().contains("missing field `acceptsInput`"),
            "{error}"
        );
    }
}

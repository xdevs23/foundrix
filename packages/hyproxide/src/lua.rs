//! Lua source text built from typed values.
//!
//! Hyprland runs the text of a `dispatch` request as the argument of
//! `hl.dispatch(...)` and the text of an `eval` request as Lua code. The types
//! here render the literals and calls that go into that text.

use std::fmt::{self, Display, Formatter, Write as _};

/// A Lua literal.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Boolean(bool),
    Integer(i64),
    Number(f64),
    String(String),
    Table(Table),
}

/// A Lua table with named fields, rendered in the order they were set.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Table(Vec<(&'static str, Value)>);

impl Table {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// This table with `key` set to `value`, in place of an earlier value of
    /// `key`.
    #[must_use]
    pub fn with(mut self, key: &'static str, value: impl Into<Value>) -> Self {
        let value = value.into();
        match self.0.iter_mut().find(|(field, _)| *field == key) {
            Some((_, earlier)) => *earlier = value,
            None => self.0.push((key, value)),
        }
        self
    }
}

/// A call of a Lua function named by its full path, such as
/// `hl.dsp.window.close`.
#[derive(Debug, Clone, PartialEq)]
pub struct Call {
    function: &'static str,
    arguments: Vec<Value>,
}

impl Call {
    #[must_use]
    pub fn new(function: &'static str, arguments: Vec<Value>) -> Self {
        Self {
            function,
            arguments,
        }
    }
}

impl Display for Value {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        match self {
            Value::Boolean(value) => write!(f, "{value}"),
            Value::Integer(value) => write!(f, "{value}"),
            Value::Number(value) => write_number(f, *value),
            Value::String(value) => write_string(f, value),
            Value::Table(table) => write!(f, "{table}"),
        }
    }
}

impl Display for Table {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        if self.0.is_empty() {
            return f.write_str("{}");
        }
        f.write_str("{ ")?;
        for (index, (key, value)) in self.0.iter().enumerate() {
            if index > 0 {
                f.write_str(", ")?;
            }
            write!(f, "{key} = {value}")?;
        }
        f.write_str(" }")
    }
}

impl Display for Call {
    fn fmt(&self, f: &mut Formatter<'_>) -> fmt::Result {
        write!(f, "{}(", self.function)?;
        for (index, argument) in self.arguments.iter().enumerate() {
            if index > 0 {
                f.write_str(", ")?;
            }
            write!(f, "{argument}")?;
        }
        f.write_char(')')
    }
}

/// Lua has no literal for infinity and NaN, so those become the divisions
/// that yield them.
fn write_number(f: &mut Formatter<'_>, value: f64) -> fmt::Result {
    if value.is_nan() {
        f.write_str("(0/0)")
    } else if value.is_infinite() {
        f.write_str(if value > 0.0 { "(1/0)" } else { "(-1/0)" })
    } else {
        write!(f, "{value}")
    }
}

fn write_string(f: &mut Formatter<'_>, value: &str) -> fmt::Result {
    f.write_char('"')?;
    for c in value.chars() {
        match c {
            '"' => f.write_str("\\\"")?,
            '\\' => f.write_str("\\\\")?,
            '\n' => f.write_str("\\n")?,
            '\r' => f.write_str("\\r")?,
            '\t' => f.write_str("\\t")?,
            // Lua reads up to three decimal digits after a backslash as a byte.
            c if c.is_ascii_control() => write!(f, "\\{:03}", u32::from(c))?,
            c => f.write_char(c)?,
        }
    }
    f.write_char('"')
}

impl From<bool> for Value {
    fn from(value: bool) -> Self {
        Value::Boolean(value)
    }
}

impl From<i32> for Value {
    fn from(value: i32) -> Self {
        Value::Integer(value.into())
    }
}

impl From<u32> for Value {
    fn from(value: u32) -> Self {
        Value::Integer(value.into())
    }
}

impl From<i64> for Value {
    fn from(value: i64) -> Self {
        Value::Integer(value)
    }
}

impl From<f64> for Value {
    fn from(value: f64) -> Self {
        Value::Number(value)
    }
}

impl From<String> for Value {
    fn from(value: String) -> Self {
        Value::String(value)
    }
}

impl From<&str> for Value {
    fn from(value: &str) -> Self {
        Value::String(value.to_owned())
    }
}

impl From<Table> for Value {
    fn from(table: Table) -> Self {
        Value::Table(table)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn string(value: &str) -> String {
        Value::from(value).to_string()
    }

    #[test]
    fn strings_are_quoted_and_escaped() {
        assert_eq!(string(""), r#""""#);
        assert_eq!(string("plain"), r#""plain""#);
        assert_eq!(string("q\"b\\n\nr\rt\t"), r#""q\"b\\n\nr\rt\t""#);
        assert_eq!(string("\u{0}\u{1b}\u{7f}1"), r#""\000\027\1271""#);
        assert_eq!(string("…"), "\"…\"");
    }

    #[test]
    fn numbers() {
        assert_eq!(Value::from(-3).to_string(), "-3");
        assert_eq!(Value::from(1.5).to_string(), "1.5");
        assert_eq!(Value::from(2.0).to_string(), "2");
        assert_eq!(Value::from(f64::INFINITY).to_string(), "(1/0)");
        assert_eq!(Value::from(f64::NEG_INFINITY).to_string(), "(-1/0)");
        assert_eq!(Value::from(f64::NAN).to_string(), "(0/0)");
    }

    #[test]
    fn tables_keep_the_order_of_their_fields() {
        assert_eq!(Table::new().to_string(), "{}");
        let table = Table::new().with("b", true).with("a", 1).with("b", false);
        assert_eq!(table.to_string(), "{ b = false, a = 1 }");
    }

    #[test]
    fn calls() {
        let call = Call::new(
            "hl.dsp.focus",
            vec![Table::new().with("workspace", "3").into()],
        );
        assert_eq!(call.to_string(), r#"hl.dsp.focus({ workspace = "3" })"#);
        assert_eq!(
            Call::new("hl.dsp.exit", Vec::new()).to_string(),
            "hl.dsp.exit()"
        );
    }
}

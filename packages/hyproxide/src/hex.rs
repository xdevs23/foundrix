//! Hyprland writes addresses and stable ids as lowercase hex digits alone
//! (`{:x}`), so that is the only form read back.

pub(crate) fn read(text: &str) -> Option<u64> {
    let lowercase_digits = !text.is_empty()
        && text
            .bytes()
            .all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f'));
    lowercase_digits
        .then(|| u64::from_str_radix(text, 16).ok())
        .flatten()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lowercase_digits_alone() {
        assert_eq!(read("573106b0db30"), Some(0x5731_06b0_db30));
        assert_eq!(read("0"), Some(0));
        for text in ["", "0x1", "+ff", "FF", "fF", " ff", "1ffffffffffffffff"] {
            assert_eq!(read(text), None, "{text:?}");
        }
    }
}

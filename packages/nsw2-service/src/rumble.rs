//! Rumble HID output report encoding for the NSO GameCube Controller.
//!
//! The encoding is **not** the Joy-Con / Pro Controller dekuNukem format
//! (Report ID `0x10`, 8-byte HF/LF payload). The NSO GC controller's HID
//! descriptor only declares one output report — `0x03`, 63-byte payload —
//! and its rumble vocabulary lives inside that report in a structure
//! that mirrors HandHeldLegend's procon2tool for the Pro Controller 2:
//!
//! ```text
//! byte  0       report ID                   = 0x03
//! byte  1       0x50 | (counter & 0x0F)     ; left side header
//! bytes 2..7    5 bytes haptic data         ; left actuator
//! bytes 7..17   zeros
//! byte 17       0x50 | (counter & 0x0F)     ; right side header (mirrored)
//! bytes 18..23  5 bytes haptic data         ; right actuator
//! bytes 23..64  zeros
//! ```
//!
//! The 5-byte haptic words encode frequency/amplitude in some Nintendo-
//! internal scheme we haven't decoded yet. For v1 we toggle between a
//! fixed "rumble on" pattern (lifted from procon2tool's test patterns)
//! and an all-zero "rumble off" pattern. Per-amplitude scaling is a
//! follow-up once we've reverse-engineered the haptic word format.
//!
//! Source: HandHeldLegend's procon2tool (WebHID test-haptic feature),
//! `procon2tool/index.html` lines 530–700 of
//! <https://github.com/HandHeldLegend/handheldlegend.github.io>.

/// HID output report ID. Per the controller's HID report descriptor this
/// is the *only* output report it accepts (size 63 bytes after the ID).
const REPORT_ID: u8 = 0x03;

/// Total wire length: 1 byte report ID + 63 bytes payload.
pub const PACKET_LEN: usize = 64;

/// procon2tool's first test pattern. Produces audible/feelable rumble on
/// the Pro Controller 2 — we're betting it does likewise on the NSO GC
/// controller because they share Nintendo's "Nwcp/NS" protocol family.
const HAPTIC_ON: [u8; 5] = [0x90, 0x31, 0x10, 0x9e, 0x00];

/// All-zero haptic word. Stops rumble on procon2tool; expected to do the
/// same here.
const HAPTIC_OFF: [u8; 5] = [0x00, 0x00, 0x00, 0x00, 0x00];

/// Build a "rumble off" packet for both sides.
pub fn neutral_packet(counter: u8) -> [u8; PACKET_LEN] {
    build_packet(counter, &HAPTIC_OFF, &HAPTIC_OFF)
}

/// Build a "rumble on" packet on both sides. Amplitudes are accepted but
/// currently ignored — the haptic-word encoding for varying amplitude
/// isn't decoded yet, so we have one on-pattern and one off-pattern.
pub fn rumble_packet(counter: u8, left_amp: f32, right_amp: f32) -> [u8; PACKET_LEN] {
    let l = if left_amp > 0.0 { &HAPTIC_ON } else { &HAPTIC_OFF };
    let r = if right_amp > 0.0 { &HAPTIC_ON } else { &HAPTIC_OFF };
    build_packet(counter, l, r)
}

fn build_packet(counter: u8, left: &[u8; 5], right: &[u8; 5]) -> [u8; PACKET_LEN] {
    let mut p = [0u8; PACKET_LEN];
    p[0] = REPORT_ID;
    let header = 0x50 | (counter & 0x0F);
    p[1] = header;
    p[2..7].copy_from_slice(left);
    p[17] = header;
    p[18..23].copy_from_slice(right);
    p
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn neutral_packet_zero_haptic() {
        let p = neutral_packet(0);
        assert_eq!(p[0], 0x03);
        assert_eq!(p[1], 0x50);
        assert_eq!(&p[2..7], &[0u8; 5]);
        assert_eq!(p[17], 0x50);
        assert_eq!(&p[18..23], &[0u8; 5]);
    }

    #[test]
    fn rumble_packet_carries_haptic_on() {
        let p = rumble_packet(0, 0.5, 0.5);
        assert_eq!(p[0], 0x03);
        assert_eq!(&p[2..7], &HAPTIC_ON);
        assert_eq!(&p[18..23], &HAPTIC_ON);
    }

    #[test]
    fn rumble_packet_zero_amp_is_off() {
        let p = rumble_packet(0, 0.0, 0.0);
        assert_eq!(&p[2..7], &HAPTIC_OFF);
        assert_eq!(&p[18..23], &HAPTIC_OFF);
    }

    #[test]
    fn counter_masked_to_low_nibble() {
        let p = rumble_packet(0xFF, 0.0, 0.0);
        assert_eq!(p[1], 0x5F);
        assert_eq!(p[17], 0x5F);
    }

    #[test]
    fn full_packet_length() {
        let p = neutral_packet(0);
        assert_eq!(p.len(), 64);
    }
}

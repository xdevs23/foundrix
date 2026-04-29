//! Decoding of the 64-byte HID input report the NSO GameCube Controller
//! emits once it's in HID mode.
//!
//! Layout (offsets into `payload = report[1..]`, after the report ID):
//!
//! | offset      | meaning                                          |
//! |-------------|--------------------------------------------------|
//! | `0x02..=04` | 24 button bits (see [`KEY_MAP`])                 |
//! | `0x05..=07` | left stick, two 12-bit values packed into 3 B   |
//! | `0x08..=0A` | right stick (C-stick), same packing             |
//! | `0x0C`      | left analog trigger,  raw byte 0..=255          |
//! | `0x0D`      | right analog trigger, raw byte 0..=255          |
//!
//! Trigger raw values sit at ~0x24 (36) at rest and reach ~0xF0 (240) on
//! a normal full press, with up to 0xFF (255) on a hard press. We emit
//! the byte verbatim — Dolphin and other consumers can apply their own
//! calibration if they care; we don't want to flatten "soft full press"
//! and "hard full press" into the same 255.

use evdev::KeyCode;

/// Decoded snapshot of one HID input report. Stick X/Y values are already
/// adjusted to match the Linux gamepad convention (up = negative, east =
/// positive). Trigger values are passed through verbatim.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ControllerState {
    pub buttons: [u8; 3],
    pub stick_l: (i16, i16),
    pub stick_r: (i16, i16),
    pub trigger_l: u8,
    pub trigger_r: u8,
}

fn unpack_12bit(triplet: &[u8]) -> (u16, u16) {
    let a = (triplet[0] as u16) | (((triplet[1] as u16) & 0x0F) << 8);
    let b = ((triplet[1] as u16) >> 4) | ((triplet[2] as u16) << 4);
    (a, b)
}

/// 12-bit centered axis -> i16 axis covering ±32767. Multiplying by 16
/// is just `<<4`, which spreads the 12-bit range over 16 bits cleanly.
fn axis_from_12bit(v: u16) -> i16 {
    let centered = (v as i32) - 2048;
    (centered * 16).clamp(i16::MIN as i32, i16::MAX as i32) as i16
}

impl ControllerState {
    pub fn parse(report: &[u8]) -> Option<Self> {
        if report.len() < 0x0F {
            return None;
        }
        let payload = &report[1..];
        let buttons = [payload[0x2], payload[0x3], payload[0x4]];
        let (lx, ly) = unpack_12bit(&payload[0x5..0x8]);
        let (rx, ry) = unpack_12bit(&payload[0x8..0x0B]);
        // Y is inverted on both sticks to match the Linux gamepad convention
        // (up = negative). On the NSO GC Controller specifically, the left
        // stick's X axis is also wired in reverse — pushing east reports a
        // *decreasing* raw value — while the right (C) stick's X is normal,
        // so we invert one and not the other.
        Some(Self {
            buttons,
            stick_l: (
                axis_from_12bit(lx).saturating_neg(),
                axis_from_12bit(ly).saturating_neg(),
            ),
            stick_r: (axis_from_12bit(rx), axis_from_12bit(ry).saturating_neg()),
            trigger_l: payload[0x0C],
            trigger_r: payload[0x0D],
        })
    }
}

/// `(byte_index, bit_mask, KeyCode)`. Bits without a physical button on
/// this hardware (stick clicks, minus, two unidentified byte-2 bits) are
/// omitted entirely — keeping them around just declared phantom buttons
/// that never fire and confused autodetection in some games.
///
/// Note: evdev 0.13 only exposes the cardinal face-button names. The
/// kernel aliases `BTN_A=BTN_SOUTH`, `BTN_B=BTN_EAST`, `BTN_X=BTN_NORTH`,
/// `BTN_Y=BTN_WEST`, so consumers see the same codes either way.
pub const KEY_MAP: &[(usize, u8, KeyCode)] = &[
    (0, 0x01, KeyCode::BTN_EAST),  // B
    (0, 0x02, KeyCode::BTN_SOUTH), // A
    (0, 0x04, KeyCode::BTN_WEST),  // Y
    (0, 0x08, KeyCode::BTN_NORTH), // X
    (0, 0x10, KeyCode::BTN_TR),    // R shoulder
    (0, 0x20, KeyCode::BTN_TR2),   // ZR — also serves as the GameCube Z trigger
    (0, 0x40, KeyCode::BTN_START),
    (1, 0x01, KeyCode::BTN_DPAD_DOWN),
    (1, 0x02, KeyCode::BTN_DPAD_RIGHT),
    (1, 0x04, KeyCode::BTN_DPAD_LEFT),
    (1, 0x08, KeyCode::BTN_DPAD_UP),
    (1, 0x10, KeyCode::BTN_TL),  // L shoulder
    (1, 0x20, KeyCode::BTN_TL2), // ZL
    (2, 0x01, KeyCode::BTN_MODE), // home
    (2, 0x02, KeyCode::BTN_C),    // capture / screenshot
    (2, 0x10, KeyCode::BTN_Z),    // small "C"-marked button next to USB-C
];

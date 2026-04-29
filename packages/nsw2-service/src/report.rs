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
//! | `0x0C`      | left analog trigger,  raw 0x24..=0xF0           |
//! | `0x0D`      | right analog trigger, raw 0x24..=0xF0           |

use evdev::KeyCode;

/// Decoded snapshot of one HID input report. Stick Y values are already
/// inverted to match the Linux gamepad convention (up = negative).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ControllerState {
    pub buttons: [u8; 3],
    pub stick_l: (i16, i16),
    pub stick_r: (i16, i16),
    pub trigger_l: u8,
    pub trigger_r: u8,
}

/// Empirically determined deadband on the GameCube analog triggers.
/// Outside this band the kernel's generic HID descriptor can't tell the
/// trigger apart from "fully released" — that's why we have to remap.
const TRIG_RAW_MIN: u8 = 0x24;
const TRIG_RAW_MAX: u8 = 0xF0;

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

fn remap_trigger(raw: u8) -> u8 {
    let v = raw.clamp(TRIG_RAW_MIN, TRIG_RAW_MAX) - TRIG_RAW_MIN;
    let span = (TRIG_RAW_MAX - TRIG_RAW_MIN) as u32;
    ((v as u32 * 255) / span) as u8
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
            trigger_l: remap_trigger(payload[0x0C]),
            trigger_r: remap_trigger(payload[0x0D]),
        })
    }
}

/// `(byte_index, bit_mask, KeyCode)`. Mirrors the upstream Python's
/// mapping faithfully, including the bits whose physical button identity
/// isn't documented — those are routed to `BTN_C` / `BTN_THUMB` /
/// `BTN_THUMB2` placeholders so nothing is dropped silently. Rename once
/// we identify them on the hardware.
pub const KEY_MAP: &[(usize, u8, KeyCode)] = &[
    // Face buttons. evdev 0.13 only exposes the cardinal names — the kernel
    // aliases BTN_A=BTN_SOUTH, BTN_B=BTN_EAST, BTN_X=BTN_NORTH, BTN_Y=BTN_WEST,
    // so consumers see the same codes either way.
    (0, 0x01, KeyCode::BTN_EAST),  // B
    (0, 0x02, KeyCode::BTN_SOUTH), // A
    (0, 0x04, KeyCode::BTN_WEST),  // Y
    (0, 0x08, KeyCode::BTN_NORTH), // X
    (0, 0x10, KeyCode::BTN_TR), // R shoulder
    (0, 0x20, KeyCode::BTN_TR2), // ZR
    (0, 0x40, KeyCode::BTN_START),
    (0, 0x80, KeyCode::BTN_THUMBR), // right stick click
    (1, 0x01, KeyCode::BTN_DPAD_DOWN),
    (1, 0x02, KeyCode::BTN_DPAD_RIGHT),
    (1, 0x04, KeyCode::BTN_DPAD_LEFT),
    (1, 0x08, KeyCode::BTN_DPAD_UP),
    (1, 0x10, KeyCode::BTN_TL),  // L shoulder
    (1, 0x20, KeyCode::BTN_TL2), // ZL
    (1, 0x40, KeyCode::BTN_SELECT),
    (1, 0x80, KeyCode::BTN_THUMBL), // left stick click
    (2, 0x01, KeyCode::BTN_MODE),   // home
    (2, 0x02, KeyCode::BTN_C),      // capture? unconfirmed
    (2, 0x04, KeyCode::BTN_THUMB2), // unidentified
    (2, 0x08, KeyCode::BTN_THUMB),  // unidentified
    (2, 0x10, KeyCode::BTN_Z),      // GameCube's Z trigger button
];

//! Rumble command frame for the NSO GameCube Controller, sent on the
//! vendor-specific bulk OUT endpoint of interface 1 — the same channel
//! that carries the init handshake.
//!
//! The command is the standard NS protocol framing
//! `[cmd, 0x91, 0x00, subcmd, …payload]`, with `cmd=0x0A`, `subcmd=0x02`,
//! and a single motor-state byte at offset 8: `0x01` for motor on,
//! `0x00` for motor off. The controller has one ERM actuator (the bulge
//! in the center), no second motor, so amplitude/frequency are not
//! adjustable.

/// Wire length of a single rumble command frame.
pub const FRAME_LEN: usize = 12;

fn build_frame(motor_on: bool) -> [u8; FRAME_LEN] {
    [
        0x0A, 0x91, 0x00, 0x02, // command 0x0A, REQ, USB interface, subcommand 0x02
        0x00, 0x04, 0x00, 0x00, // payload header
        if motor_on { 0x01 } else { 0x00 }, // motor state
        0x00, 0x00, 0x00, // trailing zeros
    ]
}

/// Build a "rumble off" frame.
pub fn neutral_frame() -> [u8; FRAME_LEN] {
    build_frame(false)
}

/// Build a rumble frame. Amplitudes collapse to a single binary
/// decision: any non-zero amplitude on either side activates the motor.
pub fn rumble_frame(left_amp: f32, right_amp: f32) -> [u8; FRAME_LEN] {
    build_frame(left_amp > 0.0 || right_amp > 0.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn neutral_frame_motor_byte_is_zero() {
        let f = neutral_frame();
        assert_eq!(&f[..4], &[0x0A, 0x91, 0x00, 0x02]);
        assert_eq!(f[8], 0x00);
    }

    #[test]
    fn rumble_frame_motor_byte_is_one() {
        let f = rumble_frame(0.5, 0.0);
        assert_eq!(f[8], 0x01);
    }

    #[test]
    fn zero_amplitudes_off() {
        assert_eq!(rumble_frame(0.0, 0.0)[8], 0x00);
    }

    #[test]
    fn always_12_bytes() {
        assert_eq!(neutral_frame().len(), FRAME_LEN);
        assert_eq!(rumble_frame(1.0, 0.0).len(), FRAME_LEN);
    }
}

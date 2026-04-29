//! Userspace driver/service for Nintendo Switch 2 controllers (057e:2066,
//! 057e:2067, 057e:2069, 057e:2073). On Switch 2 these controllers boot up
//! speaking Nintendo's proprietary "Nwcp/NS" protocol over USB rather than
//! standard HID; a per-vendor handshake on bulk interface 1 is required
//! before the kernel's HID layer can pick them up. Even after that, the
//! kernel's generic HID descriptor mismaps several inputs (Y axis flipped,
//! analog triggers stuck below their deadband, capture button unmapped),
//! so we expose the controller as our own properly-laid-out virtual gamepad.
//!
//! Current scope: NSO GameCube Controller (057e:2073) — init handshake,
//! plus an HID-to-uinput translation bridge for buttons, sticks, and
//! analog triggers. Pro Controller 2, Joy-Con 2 L/R, and rumble are still
//! to come.

use anyhow::Result;

mod bridge;
mod init;
mod report;
// Retained for future use when rumble routing through the vendor bulk
// endpoint is added; see comment in bridge.rs::hid_loop.
#[allow(dead_code)]
mod rumble;

fn main() -> Result<()> {
    init::run()?;
    bridge::run()
}

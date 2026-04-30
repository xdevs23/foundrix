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
//! HID-to-uinput translation bridge for buttons, sticks, and analog
//! triggers, plus binary on/off rumble for the central ERM motor. Pro
//! Controller 2 and Joy-Con 2 L/R are still to come.

use anyhow::Result;

mod bridge;
mod init;
mod report;
mod rumble;

fn main() -> Result<()> {
    let usb = init::run()?;
    bridge::run(usb)
}

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
//!
//! When started with a sysfs path argument (e.g. `/sys/bus/usb/devices/1-1.2`)
//! the service targets that specific controller. Without an argument it
//! auto-detects the first available controller (legacy behaviour).

use std::path::Path;

use anyhow::{Context, Result};

mod bridge;
mod init;
mod poll;
mod report;
mod rumble;

fn parse_sysfs_path(path: &str) -> Result<(u8, u8)> {
    let p = Path::new(path);
    let busnum = std::fs::read_to_string(p.join("busnum"))
        .with_context(|| format!("read busnum from {path}"))?
        .trim()
        .parse::<u8>()
        .context("parse busnum")?;
    let devnum = std::fs::read_to_string(p.join("devnum"))
        .with_context(|| format!("read devnum from {path}"))?
        .trim()
        .parse::<u8>()
        .context("parse devnum")?;
    Ok((busnum, devnum))
}

fn main() -> Result<()> {
    let (target_bus, target_dev) = match std::env::args().nth(1) {
        Some(path) => {
            let (bus, dev) = parse_sysfs_path(&path)?;
            println!(
                "nsw2-service: targeting USB device {bus}:{dev} ({path})"
            );
            (Some(bus), Some(dev))
        }
        None => {
            println!(
                "nsw2-service: auto-detecting first available controller"
            );
            (None, None)
        }
    };

    let usb = init::run(target_bus, target_dev)?;
    bridge::run(usb, target_bus, target_dev)
}

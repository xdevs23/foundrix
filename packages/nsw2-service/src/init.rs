//! Sends the proprietary handshake on bulk interface 1 that switches an
//! NSO GameCube Controller (057e:2073) out of Nintendo's "Nwcp/NS"
//! protocol and into HID mode. Once these packets land, the kernel's HID
//! layer picks the controller up.
//!
//! Port of the init phase of ikz87/NSW2-controller-enabler's `enable_hid.py`.

use std::thread;
use std::time::Duration;

use anyhow::{Context, Result, anyhow};
use rusb::{Direction, TransferType, UsbContext};

const VENDOR_ID: u16 = 0x057E;
const PRODUCT_ID: u16 = 0x2073;
const INTERFACE: u8 = 1;

const WRITE_TIMEOUT: Duration = Duration::from_millis(1000);
const DRAIN_TIMEOUT: Duration = Duration::from_millis(100);
const POST_WRITE_SETTLE: Duration = Duration::from_millis(10);
const INTER_PACKET_DELAY: Duration = Duration::from_millis(50);

/// The 17 packets the controller expects, in order, to switch from its
/// native NS protocol into HID mode. Each starts with a one-byte command
/// code; the remaining structure is opaque (reverse-engineered upstream).
const INIT_SEQUENCE: &[&[u8]] = &[
    // Phase 1: identity / setup
    &[
        0x03, 0x91, 0x00, 0x0D, 0x00, 0x08, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF,
    ],
    &[0x07, 0x91, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
    &[0x16, 0x91, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
    // Phase 2: pairing-style exchange (MAC request, LTK request)
    &[
        0x15, 0x91, 0x00, 0x01, 0x00, 0x0E, 0x00, 0x00, 0x00, 0x02, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    ],
    &[
        0x15, 0x91, 0x00, 0x02, 0x00, 0x11, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    ],
    &[0x15, 0x91, 0x00, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00],
    // Phase 3: feature configuration (LEDs, IMU, haptics)
    &[
        0x09, 0x91, 0x00, 0x07, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00,
    ],
    &[
        0x0C, 0x91, 0x00, 0x02, 0x00, 0x04, 0x00, 0x00, 0x27, 0x00, 0x00, 0x00,
    ],
    &[0x11, 0x91, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00],
    &[
        0x0A, 0x91, 0x00, 0x08, 0x00, 0x14, 0x00, 0x00, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0x35, 0x00, 0x46, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ],
    &[
        0x0C, 0x91, 0x00, 0x04, 0x00, 0x04, 0x00, 0x00, 0x27, 0x00, 0x00, 0x00,
    ],
    &[
        0x03, 0x91, 0x00, 0x0A, 0x00, 0x04, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00,
    ],
    // Phase 4: finalize, set player LED
    &[0x10, 0x91, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
    &[0x01, 0x91, 0x00, 0x0C, 0x00, 0x00, 0x00, 0x00],
    &[0x03, 0x91, 0x00, 0x01, 0x00, 0x00, 0x00],
    &[0x0A, 0x91, 0x00, 0x02, 0x00, 0x04, 0x00, 0x00, 0x03, 0x00, 0x00],
    &[
        0x09, 0x91, 0x00, 0x07, 0x00, 0x08, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00,
    ],
];

struct Endpoints {
    bulk_out: u8,
    bulk_in: Option<u8>,
}

fn find_endpoints<T: UsbContext>(device: &rusb::Device<T>, interface: u8) -> Result<Endpoints> {
    let cfg = device
        .active_config_descriptor()
        .context("read active configuration descriptor")?;
    let iface = cfg
        .interfaces()
        .find(|i| i.number() == interface)
        .ok_or_else(|| anyhow!("interface {interface} not present"))?;
    let alt = iface
        .descriptors()
        .next()
        .ok_or_else(|| anyhow!("interface {interface} has no alternate setting"))?;

    let mut bulk_out = None;
    let mut bulk_in = None;
    for ep in alt.endpoint_descriptors() {
        if ep.transfer_type() != TransferType::Bulk {
            continue;
        }
        match ep.direction() {
            Direction::Out if bulk_out.is_none() => bulk_out = Some(ep.address()),
            Direction::In if bulk_in.is_none() => bulk_in = Some(ep.address()),
            _ => {}
        }
    }

    Ok(Endpoints {
        bulk_out: bulk_out
            .ok_or_else(|| anyhow!("no bulk OUT endpoint on interface {interface}"))?,
        bulk_in,
    })
}

/// A claimed handle to interface 1 plus the bulk OUT endpoint address —
/// returned from [`run`] so the bridge can keep the channel alive and use
/// it for runtime commands (rumble, etc.).
pub struct UsbCommandChannel {
    pub handle: rusb::DeviceHandle<rusb::Context>,
    pub bulk_out: u8,
}

pub fn run() -> Result<UsbCommandChannel> {
    let context = rusb::Context::new().context("initialize libusb")?;

    let device = context
        .devices()?
        .iter()
        .find(|d| {
            d.device_descriptor()
                .map(|dd| dd.vendor_id() == VENDOR_ID && dd.product_id() == PRODUCT_ID)
                .unwrap_or(false)
        })
        .ok_or_else(|| {
            anyhow!("device {VENDOR_ID:04X}:{PRODUCT_ID:04X} (NS2 GameCube Controller) not found")
        })?;

    let endpoints = find_endpoints(&device, INTERFACE)?;

    let handle = device.open().context("open device")?;
    // Detach hid-generic / hid-nintendo if it's already grabbed iface 1, and
    // reattach it automatically when our handle drops.
    let _ = handle.set_auto_detach_kernel_driver(true);
    handle
        .claim_interface(INTERFACE)
        .with_context(|| format!("claim interface {INTERFACE}"))?;

    let mut drain_buf = [0u8; 64];
    for (idx, packet) in INIT_SEQUENCE.iter().enumerate() {
        handle
            .write_bulk(endpoints.bulk_out, packet, WRITE_TIMEOUT)
            .with_context(|| {
                format!(
                    "write init packet #{} (cmd 0x{:02X})",
                    idx + 1,
                    packet[0]
                )
            })?;
        // Drain any reply so the next write isn't blocked behind a stale buffer.
        // The controller doesn't always reply — timeouts are normal here.
        if let Some(ep_in) = endpoints.bulk_in {
            thread::sleep(POST_WRITE_SETTLE);
            let _ = handle.read_bulk(ep_in, &mut drain_buf, DRAIN_TIMEOUT);
        }
        thread::sleep(INTER_PACKET_DELAY);
    }

    println!(
        "nsw2-service: sent {} init packets to {VENDOR_ID:04X}:{PRODUCT_ID:04X}",
        INIT_SEQUENCE.len()
    );
    // Deliberately do *not* release interface 1: post-init runtime commands
    // (rumble) also go out on this bulk OUT endpoint. Releasing here would
    // make the bridge's later writes fail. The handle is dropped when the
    // bridge exits, at which point libusb releases the interface.
    Ok(UsbCommandChannel {
        handle,
        bulk_out: endpoints.bulk_out,
    })
}

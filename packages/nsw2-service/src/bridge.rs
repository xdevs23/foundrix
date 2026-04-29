//! HID-to-uinput bridge for the NSO GameCube Controller.
//!
//! After [`crate::init::run`] has switched the controller into HID mode,
//! this module:
//!
//! 1. Polls hidapi for `057E:2073` to appear (the kernel takes a moment
//!    to set up `/dev/hidrawN`).
//! 2. Builds a virtual gamepad via uinput with the right key + axis layout.
//! 3. Loops: read a 64-byte input report, decode, emit changed events.
//!
//! Force-feedback is intentionally not declared yet — that's a separate step.

use std::thread;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow};
use evdev::{
    AbsInfo, AbsoluteAxisCode, AttributeSet, BusType, EventType, InputEvent, InputId, KeyCode,
    UinputAbsSetup,
    uinput::VirtualDevice,
};
use hidapi::{HidApi, HidDevice};

use crate::report::{self, ControllerState};

const VENDOR_ID: u16 = 0x057E;
const PRODUCT_ID: u16 = 0x2073;

/// How long to wait for `/dev/hidrawN` to appear after init.
const HIDRAW_OPEN_TIMEOUT: Duration = Duration::from_secs(3);
const HIDRAW_OPEN_INTERVAL: Duration = Duration::from_millis(100);

/// HID read timeout, in milliseconds. We wake periodically so we don't
/// miss SIGTERM forever (systemd's stop sequence).
const HID_READ_TIMEOUT_MS: i32 = 1000;
const HID_REPORT_BUF: usize = 64;

const STICK_MIN: i32 = i16::MIN as i32;
const STICK_MAX: i32 = i16::MAX as i32;
/// Trigger raw byte range. The hardware sits at ~36 at rest and reaches
/// ~240 on a normal full press, but can hit 255 with a hard press, so we
/// declare the whole byte range and pass it through unmodified.
const TRIG_MIN: i32 = 0;
const TRIG_MAX: i32 = 255;

pub fn run() -> Result<()> {
    let mut api = HidApi::new().context("initialize hidapi")?;
    let device = open_with_retry(&mut api).context("open hidraw device")?;

    let mut vdev = build_virtual_device().context("create virtual gamepad via uinput")?;

    println!(
        "nsw2-service: bridging HID -> uinput for {VENDOR_ID:04X}:{PRODUCT_ID:04X}; \
         press Ctrl-C or unplug the controller to exit"
    );

    let mut buf = [0u8; HID_REPORT_BUF];
    let mut last = ControllerState::default();
    loop {
        match device.read_timeout(&mut buf, HID_READ_TIMEOUT_MS) {
            Ok(0) => continue, // hidapi convention: 0 = timeout, not EOF
            Ok(n) => {
                if let Some(state) = ControllerState::parse(&buf[..n]) {
                    emit_state(&mut vdev, &state, &last)?;
                    last = state;
                }
            }
            Err(e) => {
                // Disconnect, fd revoked, etc. — bail cleanly so the
                // service can be re-fired by udev on the next plug-in.
                return Err(anyhow!("HID read failed (controller likely unplugged): {e}"));
            }
        }
    }
}

fn open_with_retry(api: &mut HidApi) -> Result<HidDevice> {
    let deadline = Instant::now() + HIDRAW_OPEN_TIMEOUT;
    loop {
        match api.open(VENDOR_ID, PRODUCT_ID) {
            Ok(d) => return Ok(d),
            Err(e) => {
                if Instant::now() >= deadline {
                    return Err(anyhow!(
                        "could not open HID device {VENDOR_ID:04X}:{PRODUCT_ID:04X} \
                         within {:?}: {e}",
                        HIDRAW_OPEN_TIMEOUT
                    ));
                }
                thread::sleep(HIDRAW_OPEN_INTERVAL);
                let _ = api.refresh_devices();
            }
        }
    }
}

fn build_virtual_device() -> Result<VirtualDevice> {
    let mut keys = AttributeSet::<KeyCode>::new();
    for &(_, _, key) in report::KEY_MAP {
        keys.insert(key);
    }

    // fuzz: kernel suppresses changes smaller than this, killing 250Hz HID
    // polling jitter at rest. flat: informational center-deadzone hint that
    // games may consult — we don't apply it ourselves so apps get full
    // precision when they want it.
    let stick = AbsInfo::new(0, STICK_MIN, STICK_MAX, 64, 512, 0);
    let trigger = AbsInfo::new(0, TRIG_MIN, TRIG_MAX, 2, 4, 0);

    let dev = VirtualDevice::builder()?
        .name("Nintendo Switch 2 NSO GameCube Controller")
        .input_id(InputId::new(BusType::BUS_USB, VENDOR_ID, PRODUCT_ID, 0x0001))
        .with_keys(&keys)?
        .with_absolute_axis(&UinputAbsSetup::new(AbsoluteAxisCode::ABS_X, stick))?
        .with_absolute_axis(&UinputAbsSetup::new(AbsoluteAxisCode::ABS_Y, stick))?
        .with_absolute_axis(&UinputAbsSetup::new(AbsoluteAxisCode::ABS_RX, stick))?
        .with_absolute_axis(&UinputAbsSetup::new(AbsoluteAxisCode::ABS_RY, stick))?
        .with_absolute_axis(&UinputAbsSetup::new(AbsoluteAxisCode::ABS_Z, trigger))?
        .with_absolute_axis(&UinputAbsSetup::new(AbsoluteAxisCode::ABS_RZ, trigger))?
        .build()?;
    Ok(dev)
}

fn emit_state(
    vdev: &mut VirtualDevice,
    state: &ControllerState,
    last: &ControllerState,
) -> Result<()> {
    // Reasonable upper bound: 21 buttons + 6 axes + 1 syn = 28
    let mut events: Vec<InputEvent> = Vec::with_capacity(32);

    for &(byte, mask, key) in report::KEY_MAP {
        let now = state.buttons[byte] & mask != 0;
        let prev = last.buttons[byte] & mask != 0;
        if now != prev {
            events.push(InputEvent::new(EventType::KEY.0, key.code(), now as i32));
        }
    }

    if state.stick_l.0 != last.stick_l.0 {
        events.push(abs_event(AbsoluteAxisCode::ABS_X, state.stick_l.0));
    }
    if state.stick_l.1 != last.stick_l.1 {
        events.push(abs_event(AbsoluteAxisCode::ABS_Y, state.stick_l.1));
    }
    if state.stick_r.0 != last.stick_r.0 {
        events.push(abs_event(AbsoluteAxisCode::ABS_RX, state.stick_r.0));
    }
    if state.stick_r.1 != last.stick_r.1 {
        events.push(abs_event(AbsoluteAxisCode::ABS_RY, state.stick_r.1));
    }
    if state.trigger_l != last.trigger_l {
        events.push(abs_event(AbsoluteAxisCode::ABS_Z, state.trigger_l as i16));
    }
    if state.trigger_r != last.trigger_r {
        events.push(abs_event(AbsoluteAxisCode::ABS_RZ, state.trigger_r as i16));
    }

    if !events.is_empty() {
        vdev.emit(&events).context("emit uinput events")?;
    }
    Ok(())
}

fn abs_event(code: AbsoluteAxisCode, value: i16) -> InputEvent {
    InputEvent::new(EventType::ABSOLUTE.0, code.0, value as i32)
}

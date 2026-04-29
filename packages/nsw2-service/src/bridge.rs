//! HID-to-uinput bridge plus rumble round-trip for the NSO GameCube Controller.
//!
//! Threading model:
//!
//! * **HID thread** owns the [`HidDevice`]. It reads input reports and
//!   sends parsed [`ControllerState`]s on the *state channel*. It also
//!   receives [`RumbleCmd`]s on the *rumble channel* and writes the
//!   corresponding HID output reports back to the controller.
//!
//! * **Main thread** owns the [`VirtualDevice`]. It drains the state
//!   channel and emits to uinput, and it drains kernel-side FF events
//!   off the vdev fd (put in `O_NONBLOCK`), translating play/stop into
//!   `RumbleCmd`s for the HID thread.
//!
//! Two unidirectional `mpsc` channels, no shared mutable state.

use std::collections::{BTreeSet, HashMap};
use std::io;
use std::os::fd::{AsFd, AsRawFd, BorrowedFd};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow};
use evdev::{
    AbsInfo, AbsoluteAxisCode, AttributeSet, BusType, EventSummary, EventType, FFEffectCode,
    FFEffectKind, FFStatusCode, InputEvent, InputId, KeyCode, UInputCode, UinputAbsSetup,
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
/// miss SIGTERM forever (systemd's stop sequence) and so the rumble
/// channel gets drained between reads.
const HID_READ_TIMEOUT_MS: i32 = 50;
const HID_REPORT_BUF: usize = 64;

/// Roughly one HID frame at the controller's ~250 Hz polling rate. We
/// block on the state channel up to this long before re-checking FF
/// events, balancing FF latency vs. wakeup count when idle.
const MAIN_TICK: Duration = Duration::from_millis(4);

/// How many concurrent FF effects the kernel can upload before we start
/// rejecting them. Plenty for normal use; games rarely use more than 2.
const MAX_FF_EFFECTS: u32 = 16;

const STICK_MIN: i32 = i16::MIN as i32;
const STICK_MAX: i32 = i16::MAX as i32;
const TRIG_MIN: i32 = 0;
const TRIG_MAX: i32 = 255;

/// Commands the main thread sends to the HID thread to change rumble state.
#[derive(Debug, Clone, Copy)]
enum RumbleCmd {
    /// Play with the given strong/weak magnitudes (kernel u16 range).
    Play { strong: u16, weak: u16 },
    /// Silence both motors.
    Stop,
}

pub fn run() -> Result<()> {
    let mut api = HidApi::new().context("initialize hidapi")?;
    let hid = open_with_retry(&mut api).context("open hidraw device")?;

    let mut vdev = build_virtual_device().context("create virtual gamepad via uinput")?;
    set_nonblocking(vdev.as_fd()).context("put vdev fd in O_NONBLOCK")?;

    let (state_tx, state_rx) = mpsc::channel::<ControllerState>();
    let (rumble_tx, rumble_rx) = mpsc::channel::<RumbleCmd>();

    println!(
        "nsw2-service: bridging HID -> uinput for {VENDOR_ID:04X}:{PRODUCT_ID:04X}; \
         press Ctrl-C or unplug the controller to exit"
    );

    let hid_handle = thread::spawn(move || hid_loop(hid, state_tx, rumble_rx));

    let result = main_loop(&mut vdev, state_rx, rumble_tx);

    // Whatever happens, surface the HID thread's verdict — its error is
    // the most informative one (controller unplugged, etc.).
    let hid_result = hid_handle.join().map_err(|_| anyhow!("HID thread panicked"))?;
    match (result, hid_result) {
        (Err(e), _) => Err(e),
        (Ok(()), Err(e)) => Err(e),
        (Ok(()), Ok(())) => Ok(()),
    }
}

fn main_loop(
    vdev: &mut VirtualDevice,
    state_rx: mpsc::Receiver<ControllerState>,
    rumble_tx: mpsc::Sender<RumbleCmd>,
) -> Result<()> {
    let mut last = ControllerState::default();
    let mut effects: HashMap<u16, FFEffectKind> = HashMap::new();
    let mut available_ids: BTreeSet<u16> = (0..MAX_FF_EFFECTS as u16).collect();

    loop {
        match state_rx.recv_timeout(MAIN_TICK) {
            Ok(state) => {
                emit_state(vdev, &state, &last)?;
                last = state;
                while let Ok(state) = state_rx.try_recv() {
                    emit_state(vdev, &state, &last)?;
                    last = state;
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                // HID thread exited (controller unplugged or fatal error).
                // Its return value carries the real reason.
                return Ok(());
            }
        }

        process_ff(vdev, &mut effects, &mut available_ids, &rumble_tx)?;
    }
}

fn hid_loop(
    hid: HidDevice,
    state_tx: mpsc::Sender<ControllerState>,
    rumble_rx: mpsc::Receiver<RumbleCmd>,
) -> Result<()> {
    let mut buf = [0u8; HID_REPORT_BUF];

    loop {
        // Rumble HID writes are disabled on this controller. The HID
        // descriptor declares output report 0x03 but writes to it cause
        // the controller's USB stack to drop off the bus within a few
        // milliseconds — confirmed empirically and corroborated by
        // RyanCopley/NSO-GameCube-Controller-Pairing-App, which notes
        // the command interface "is not accessible through the HID
        // driver". The actual rumble command path is the vendor bulk
        // endpoint on interface 1 (the channel we use for init), which
        // we don't keep open here. Drain the channel so the main thread
        // doesn't fill the queue, but drop the bytes; the threading and
        // `rumble.rs` packet builder are retained so we can wire them up
        // once we add a bulk-OUT writer.
        while rumble_rx.try_recv().is_ok() {}

        match hid.read_timeout(&mut buf, HID_READ_TIMEOUT_MS) {
            Ok(0) => continue,
            Ok(n) => {
                if let Some(state) = ControllerState::parse(&buf[..n])
                    && state_tx.send(state).is_err()
                {
                    return Ok(()); // main thread dropped the receiver
                }
            }
            Err(e) => {
                return Err(anyhow!("HID read failed (controller likely unplugged): {e}"));
            }
        }
    }
}

fn process_ff(
    vdev: &mut VirtualDevice,
    effects: &mut HashMap<u16, FFEffectKind>,
    available_ids: &mut BTreeSet<u16>,
    rumble_tx: &mpsc::Sender<RumbleCmd>,
) -> Result<()> {
    const STOPPED: i32 = FFStatusCode::FF_STATUS_STOPPED.0 as i32;
    const PLAYING: i32 = FFStatusCode::FF_STATUS_PLAYING.0 as i32;

    let events: Vec<InputEvent> = match vdev.fetch_events() {
        Ok(iter) => iter.collect(),
        Err(e) if e.kind() == io::ErrorKind::WouldBlock => return Ok(()),
        Err(e) => return Err(anyhow!("vdev.fetch_events: {e}")),
    };

    for event in events {
        match event.destructure() {
            EventSummary::UInput(uev, UInputCode::UI_FF_UPLOAD, ..) => {
                let mut upload = vdev
                    .process_ff_upload(uev)
                    .context("process FF upload")?;
                match available_ids.iter().next().copied() {
                    Some(id) => {
                        available_ids.remove(&id);
                        upload.set_effect_id(id as i16);
                        upload.set_retval(0);
                        effects.insert(id, upload.effect().kind);
                    }
                    None => {
                        upload.set_retval(-1);
                    }
                }
            }
            EventSummary::UInput(uev, UInputCode::UI_FF_ERASE, ..) => {
                let erase = vdev.process_ff_erase(uev).context("process FF erase")?;
                let id = erase.effect_id() as u16;
                effects.remove(&id);
                available_ids.insert(id);
            }
            EventSummary::ForceFeedback(.., effect_id, PLAYING) => {
                let id = effect_id.0;
                if let Some(FFEffectKind::Rumble {
                    strong_magnitude,
                    weak_magnitude,
                }) = effects.get(&id)
                {
                    let _ = rumble_tx.send(RumbleCmd::Play {
                        strong: *strong_magnitude,
                        weak: *weak_magnitude,
                    });
                }
            }
            EventSummary::ForceFeedback(.., _, STOPPED) => {
                let _ = rumble_tx.send(RumbleCmd::Stop);
            }
            _ => {}
        }
    }
    Ok(())
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

    let mut ff = AttributeSet::<FFEffectCode>::new();
    ff.insert(FFEffectCode::FF_RUMBLE);

    // fuzz: kernel suppresses changes smaller than this, killing 250Hz HID
    // polling jitter at rest. flat: informational center-deadzone hint that
    // games may consult — we don't apply it ourselves so apps get full
    // precision when they want it.
    let stick = AbsInfo::new(0, STICK_MIN, STICK_MAX, 64, 512, 0);
    /// Trigger raw byte range. The hardware sits at ~36 at rest and reaches
    /// ~240 on a normal full press, but can hit 255 with a hard press, so we
    /// declare the whole byte range and pass it through unmodified.
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
        .with_ff(&ff)?
        .with_ff_effects_max(MAX_FF_EFFECTS)
        .build()?;
    Ok(dev)
}

fn emit_state(
    vdev: &mut VirtualDevice,
    state: &ControllerState,
    last: &ControllerState,
) -> Result<()> {
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

/// Put a borrowed fd into `O_NONBLOCK`. Used so `fetch_events` returns
/// `WouldBlock` instead of waiting forever.
fn set_nonblocking(fd: BorrowedFd) -> io::Result<()> {
    let raw = fd.as_raw_fd();
    let flags = unsafe { libc::fcntl(raw, libc::F_GETFL) };
    if flags < 0 {
        return Err(io::Error::last_os_error());
    }
    let r = unsafe { libc::fcntl(raw, libc::F_SETFL, flags | libc::O_NONBLOCK) };
    if r < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

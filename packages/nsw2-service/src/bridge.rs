//! HID-to-uinput bridge plus rumble round-trip for the NSO GameCube Controller.
//!
//! Threading model:
//!
//! * **HID thread** reads input reports from `/dev/hidrawN` (opened
//!   directly for a pollable fd) and sends parsed [`ControllerState`]s
//!   on the *state channel*. It also receives [`RumbleCmd`]s on the
//!   *rumble channel* and writes the corresponding command frames out
//!   the bulk OUT endpoint.
//!
//! * **Main thread** owns the [`VirtualDevice`]. It drains the state
//!   channel and emits to uinput, and it drains kernel-side FF events
//!   off the vdev fd, translating play/stop into `RumbleCmd`s for the
//!   HID thread.
//!
//! Both threads use `poll(2)` to multiplex their fd sets — no timeouts,
//! pure event-driven wakeups. Two unidirectional `mpsc` channels
//! bridged with `eventfd(2)`, no shared mutable state.

use std::collections::{BTreeSet, HashMap};
use std::ffi::OsStr;
use std::fs::File;
use std::io::{self, Read};
use std::os::fd::{AsFd, AsRawFd, BorrowedFd};
use std::os::unix::ffi::OsStrExt;
use std::path::PathBuf;
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow};
use evdev::{
    AbsInfo, AbsoluteAxisCode, AttributeSet, BusType, EventSummary, EventType, FFEffectCode,
    FFEffectKind, FFStatusCode, InputEvent, InputId, KeyCode, UInputCode, UinputAbsSetup,
    uinput::VirtualDevice,
};
use hidapi::HidApi;

use crate::init::UsbCommandChannel;
use crate::poll::{self, PollableReceiver, PollableSender};
use crate::report::{self, ControllerState};
use crate::rumble;

const VENDOR_ID: u16 = 0x057E;
const PRODUCT_ID: u16 = 0x2073;

/// How long to wait for `/dev/hidrawN` to appear after init.
const HIDRAW_OPEN_TIMEOUT: Duration = Duration::from_secs(3);
const HIDRAW_OPEN_INTERVAL: Duration = Duration::from_millis(100);

const HID_REPORT_BUF: usize = 64;

/// Bulk-OUT write timeout for rumble frames. Generous because we don't
/// want a slow-USB hiccup to kill the bridge, but bounded so we never
/// stall input forever.
const RUMBLE_WRITE_TIMEOUT: Duration = Duration::from_millis(200);

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

pub fn run(usb: UsbCommandChannel) -> Result<()> {
    let mut api = HidApi::new().context("initialize hidapi")?;
    let hidraw_path = find_hidraw_path(&mut api).context("find hidraw device path")?;
    let hidraw = open_hidraw(&hidraw_path).context("open hidraw device")?;

    let mut vdev = build_virtual_device().context("create virtual gamepad via uinput")?;
    set_nonblocking(vdev.as_fd()).context("put vdev fd in O_NONBLOCK")?;

    let (state_tx, state_rx) =
        poll::pollable_channel::<ControllerState>().context("create state channel")?;
    let (rumble_tx, rumble_rx) =
        poll::pollable_channel::<RumbleCmd>().context("create rumble channel")?;

    println!(
        "nsw2-service: bridging HID -> uinput for {VENDOR_ID:04X}:{PRODUCT_ID:04X}; \
         press Ctrl-C or unplug the controller to exit"
    );

    let hid_handle = thread::spawn(move || hid_loop(hidraw, usb, state_tx, rumble_rx));

    let result = main_loop(&mut vdev, state_rx, rumble_tx);

    let hid_result = hid_handle.join().map_err(|_| anyhow!("HID thread panicked"))?;
    match (result, hid_result) {
        (Err(e), _) => Err(e),
        (Ok(()), Err(e)) => Err(e),
        (Ok(()), Ok(())) => Ok(()),
    }
}

fn main_loop(
    vdev: &mut VirtualDevice,
    state_rx: PollableReceiver<ControllerState>,
    rumble_tx: PollableSender<RumbleCmd>,
) -> Result<()> {
    let mut last = ControllerState::default();
    let mut effects: HashMap<u16, FFEffectKind> = HashMap::new();
    let mut available_ids: BTreeSet<u16> = (0..MAX_FF_EFFECTS as u16).collect();

    let vdev_fd = vdev.as_fd().as_raw_fd();
    let state_fd = state_rx.raw_fd();
    let mut fds = [poll::pollfd(state_fd), poll::pollfd(vdev_fd)];

    loop {
        let mut ps = poll::PollSet::new(&mut fds);
        ps.wait().context("main_loop poll")?;

        if ps.readable(0) {
            let disconnected = state_rx.drain(|state| {
                if let Err(e) = emit_state(vdev, &state, &last) {
                    eprintln!("nsw2-service: emit_state error: {e}");
                }
                last = state;
            });
            if disconnected {
                return Ok(());
            }
        }

        if ps.readable(1) || ps.has_error(1) {
            process_ff(vdev, &mut effects, &mut available_ids, &rumble_tx)?;
        }
    }
}

fn hid_loop(
    mut hidraw: File,
    usb: UsbCommandChannel,
    state_tx: PollableSender<ControllerState>,
    rumble_rx: PollableReceiver<RumbleCmd>,
) -> Result<()> {
    let hidraw_fd = hidraw.as_raw_fd();
    let rumble_fd = rumble_rx.raw_fd();
    let mut fds = [poll::pollfd(hidraw_fd), poll::pollfd(rumble_fd)];
    let mut buf = [0u8; HID_REPORT_BUF];

    loop {
        let mut ps = poll::PollSet::new(&mut fds);
        ps.wait().context("hid_loop poll")?;

        if ps.readable(1) {
            let mut latest: Option<RumbleCmd> = None;
            rumble_rx.drain(|cmd| {
                latest = Some(cmd);
            });
            if let Some(cmd) = latest {
                let frame = match cmd {
                    RumbleCmd::Stop => rumble::neutral_frame(),
                    RumbleCmd::Play { strong, weak } => rumble::rumble_frame(
                        strong as f32 / u16::MAX as f32,
                        weak as f32 / u16::MAX as f32,
                    ),
                };
                usb.handle
                    .write_bulk(usb.bulk_out, &frame, RUMBLE_WRITE_TIMEOUT)
                    .map_err(|e| anyhow!("write rumble bulk frame: {e}"))?;
            }
        }

        if ps.has_error(0) {
            return Err(anyhow!(
                "hidraw fd error (controller likely unplugged)"
            ));
        }

        if ps.readable(0) {
            loop {
                match hidraw.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        if let Some(state) = ControllerState::parse(&buf[..n])
                            && state_tx.send(state).is_err()
                        {
                            return Ok(());
                        }
                    }
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                    Err(e) => {
                        return Err(anyhow!(
                            "HID read failed (controller likely unplugged): {e}"
                        ));
                    }
                }
            }
        }
    }
}

fn process_ff(
    vdev: &mut VirtualDevice,
    effects: &mut HashMap<u16, FFEffectKind>,
    available_ids: &mut BTreeSet<u16>,
    rumble_tx: &PollableSender<RumbleCmd>,
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

fn find_hidraw_path(api: &mut HidApi) -> Result<PathBuf> {
    let deadline = Instant::now() + HIDRAW_OPEN_TIMEOUT;
    loop {
        let _ = api.refresh_devices();
        for dev in api.device_list() {
            if dev.vendor_id() == VENDOR_ID && dev.product_id() == PRODUCT_ID {
                let bytes = dev.path().to_bytes();
                return Ok(PathBuf::from(OsStr::from_bytes(bytes)));
            }
        }
        if Instant::now() >= deadline {
            return Err(anyhow!(
                "could not find HID device {VENDOR_ID:04X}:{PRODUCT_ID:04X} \
                 within {HIDRAW_OPEN_TIMEOUT:?}"
            ));
        }
        thread::sleep(HIDRAW_OPEN_INTERVAL);
    }
}

fn open_hidraw(path: &PathBuf) -> Result<File> {
    let file = File::open(path)
        .with_context(|| format!("open {}", path.display()))?;
    set_nonblocking(file.as_fd())
        .with_context(|| format!("set O_NONBLOCK on {}", path.display()))?;
    Ok(file)
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

/// Put a borrowed fd into `O_NONBLOCK`.
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

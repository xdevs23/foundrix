# Protocol notes

Technical reference for the Nintendo Switch 2 NSO GameCube Controller and
the related Switch 2 controller family.

## Device identification

| VID | PID | Controller |
|-----|-----|------------|
| 0x057E | 0x2066 | (Switch 2 controller, related family) |
| 0x057E | 0x2067 | (Switch 2 controller, related family) |
| 0x057E | 0x2069 | (Switch 2 controller, related family) |
| 0x057E | 0x2073 | NSO GameCube Controller |

## USB topology

| Interface | Class | Endpoint | Direction | Type | Max packet |
|-----------|-------|----------|-----------|------|------------|
| 0 | HID | 0x81 | IN  | Interrupt | 64 |
| 0 | HID | 0x01 | OUT | Interrupt | 64 |
| 1 | Vendor | 0x82 | IN  | Bulk | 64 |
| 1 | Vendor | 0x02 | OUT | Bulk | 64 |

The kernel HID generic driver claims interface 0 after the init handshake
completes. Interface 1 stays unclaimed and carries the proprietary
command channel.

## Init handshake

The controller boots in a non-HID mode. A 17-packet handshake on
interface 1's bulk OUT endpoint switches it into HID mode, after which
interface 0 begins emitting input reports.

Every packet starts with a one-byte command code followed by the control
byte 0x91, which marks the rest of the payload as a command structure.
Inter-packet delay is 50 ms. The bulk IN endpoint may emit short
responses to some packets and is drained between writes.

| # | Command | Sub-cmd | Length | Purpose |
|---|---------|---------|--------|---------|
|  1 | 0x03 | 0x0D | 16 | Identity / general configuration |
|  2 | 0x07 | 0x01 |  8 | — |
|  3 | 0x16 | 0x01 |  8 | — |
|  4 | 0x15 | 0x01 | 22 | Controller MAC request |
|  5 | 0x15 | 0x02 | 26 | LTK request |
|  6 | 0x15 | 0x03 |  9 | — |
|  7 | 0x09 | 0x07 | 16 | Player LED zero-init |
|  8 | 0x0C | 0x02 | 12 | IMU sample-rate setup |
|  9 | 0x11 | 0x03 |  8 | — |
| 10 | 0x0A | 0x08 | 29 | — |
| 11 | 0x0C | 0x04 | 12 | IMU enable |
| 12 | 0x03 | 0x0A | 12 | Haptics enable |
| 13 | 0x10 | 0x01 |  8 | — |
| 14 | 0x01 | 0x0C |  8 | — |
| 15 | 0x03 | 0x01 |  7 | — |
| 16 | 0x0A | 0x02 | 11 | Initial haptic state (motor byte = 0x03; same command/subcmd as the runtime rumble write below) |
| 17 | 0x09 | 0x07 | 16 | Player LED final (player 1) |

The haptics-enable packet (#12) is required before the rumble actuator
will respond to subsequent rumble commands.

## HID report descriptor

After init, interface 0 advertises:

| Report ID | Direction | Payload size | Contents |
|-----------|-----------|--------------|----------|
| 0x05 | IN  | 63 bytes | Buttons, sticks, triggers |
| 0x0A | IN  |  2 bytes | Auxiliary |
| 0x03 | OUT | 63 bytes | Vendor-defined |

Four absolute axes are declared (Usage X, Y, Rx, Rz) with logical range
0–4095 (12-bit, packed). No Ry usage is declared at the HID level.

Input polling rate is approximately 250 Hz.

## Input report 0x05

Offsets are within the 63-byte payload (i.e. into the report bytes
following the report-ID byte).

| Offset | Width | Field |
|--------|-------|-------|
| 0x02 | 1 byte  | Buttons byte 0 |
| 0x03 | 1 byte  | Buttons byte 1 |
| 0x04 | 1 byte  | Buttons byte 2 |
| 0x05 | 3 bytes | Left stick: X then Y, 12 bits each, packed |
| 0x08 | 3 bytes | Right (C) stick: X then Y, 12 bits each, packed |
| 0x0C | 1 byte  | Left analog trigger |
| 0x0D | 1 byte  | Right analog trigger |

### Stick packing

Three consecutive bytes encode two 12-bit values:

- Value A: lower 12 bits — `byte0 | ((byte1 & 0x0F) << 8)`
- Value B: upper 12 bits — `(byte1 >> 4) | (byte2 << 4)`

Each value is unsigned, range 0–4095, centered at 2048. The mechanical
deflection of the analog stick covers approximately ±1280 raw units
around center on a representative unit; the C-stick's range is similar
but slightly asymmetric.

### Stick orientation

- Left-stick X: pushing east produces a *decreasing* raw value. East
  maps to raw < 2048.
- Right (C) stick X: pushing east produces an *increasing* raw value.
  East maps to raw > 2048.
- Both sticks' Y: pushing south produces an *increasing* raw value.
  South maps to raw > 2048.

### Button bitmap

| Byte | Mask | Button |
|------|------|--------|
| 0 | 0x01 | B (face) |
| 0 | 0x02 | A (face) |
| 0 | 0x04 | Y (face) |
| 0 | 0x08 | X (face) |
| 0 | 0x10 | R (digital shoulder) |
| 0 | 0x20 | ZR (also reports as the GameCube Z trigger; single physical button) |
| 0 | 0x40 | Start / Plus |
| 0 | 0x80 | — |
| 1 | 0x01 | D-pad Down |
| 1 | 0x02 | D-pad Right |
| 1 | 0x04 | D-pad Left |
| 1 | 0x08 | D-pad Up |
| 1 | 0x10 | L (digital shoulder) |
| 1 | 0x20 | ZL |
| 1 | 0x40 | — |
| 1 | 0x80 | — |
| 2 | 0x01 | Home |
| 2 | 0x02 | Capture / screenshot |
| 2 | 0x04 | — |
| 2 | 0x08 | — |
| 2 | 0x10 | "C" — small button next to the USB-C port |
| 2 | 0x20 | — |
| 2 | 0x40 | — |
| 2 | 0x80 | — |

Bits marked "—" are reserved and never fire on this hardware. There is
no physical Minus / Select button, no analog-stick click, and no Sync.

### Trigger encoding

The two trigger bytes carry values in the range 0x24–0xFF.

| Value | Meaning |
|-------|---------|
| 0x24 | Trigger fully released (rest position) |
| 0xF0 | Trigger fully pressed under normal force |
| 0xFF | Trigger pressed under exceptional force |

The 0x00–0x23 range is never observed on this controller.

## Output report 0x03

The HID descriptor declares output report 0x03 (63-byte payload), but
writes to the HID interrupt OUT endpoint with this report ID cause the
controller to drop off the USB bus within milliseconds. This output
report is not a usable command channel.

The functional command channel (rumble, LED control, etc.) is the
vendor-specific bulk OUT endpoint on interface 1 — the same channel
that carries the init handshake. Post-init commands on this channel
follow the same `<command-byte> 0x91 …` framing as the init packets.

## Rumble

The controller contains a single eccentric rotating mass actuator in the
central bulge of the casing. There is no second actuator and no LRA;
this is not an HD Rumble device.

The actuator must be enabled during init (handshake packet 12) before it
will respond. After init, motor state is set with the following 12-byte
command on the vendor bulk OUT endpoint of interface 1:

| Offset | Width | Value | Meaning |
|--------|-------|-------|---------|
| 0 | 1 byte | 0x0A | Command code |
| 1 | 1 byte | 0x91 | Request type |
| 2 | 1 byte | 0x00 | Interface (USB) |
| 3 | 1 byte | 0x02 | Subcommand |
| 4 | 1 byte | 0x00 | — |
| 5 | 1 byte | 0x04 | Payload header |
| 6 | 2 bytes | 0x0000 | — |
| 8 | 1 byte | 0x01 / 0x00 | Motor state: 0x01 = on, 0x00 = off |
| 9 | 3 bytes | 0x000000 | Trailing zeros |

Unlike the Bluetooth rumble path used by Joy-Con 2 and Pro Controller 2,
no transaction-counter byte is required and no sequence-id wrapping
applies. The controller acts on each command immediately and holds the
motor in the requested state until a new command arrives.

## Sources

- ikz87/NSW2-controller-enabler — USB init handshake byte sequences and ordering.
- HandHeldLegend/handheldlegend.github.io (procon2tool) — Pro Controller 2 BLE rumble report layout.
- darthcloud/BlueRetro — Switch 2 controller-family BLE protocol structure, output-frame sizes, and the GC-vs-Pro-2 single-vs-dual actuator distinction.
- dekuNukem/Nintendo_Switch_Reverse_Engineering — Joy-Con/Pro Controller HD-Rumble HF/LF encoding (does not apply to the GC ERM but documents the protocol family).
- DanielOgorchock/linux (hid-nintendo branch) — kernel-side reference for Joy-Con/Pro Controller rumble encoding.
- RyanCopley/NSO-GameCube-Controller-Pairing-App — confirmed working USB rumble command (`0x0A`/`0x02`) on Linux via libusb to the bulk OUT endpoint of interface 1.
- D-tech-pro/NSO-GC-Controller-PC — corroborating cross-platform GC controller enabler implementation.

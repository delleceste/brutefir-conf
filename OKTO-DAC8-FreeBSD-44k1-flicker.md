# OKTO DAC8 STEREO — USB stream-lock loss on the 44.1 kHz clock family (FreeBSD)

## Summary

On FreeBSD the OKTO DAC8 STEREO **continuously drops and re-acquires USB
streaming lock** whenever it is fed a sample rate from the **44.1 kHz family**
(44.1 / 88.2 / 176.4 / 352.8 kHz). The front-panel display flickers between its
"playing" and "idle/pause" states several times per second, with corresponding
audible interruptions.

Feeding any rate from the **48 kHz family** (48 / 96 / 192 / 384 kHz) is
**completely stable** — no flicker, no dropouts.

The **same DAC, same USB cable, same host machine plays the 44.1 kHz family
flawlessly under Linux (ALSA `snd-usb-audio`).** The hardware is therefore fully
capable; the problem is specific to the interaction between the device's
USB-Audio implementation and the **FreeBSD `uaudio(4)` driver** on the
44.1 kHz clock domain.

This document records the technical observations so they can be discussed with
the manufacturer / firmware vendor.

---

## Test environment

| Item | Value |
|------|-------|
| DAC | OKTO RESEARCH DAC8 STEREO |
| USB IDs | idVendor `0x152A`, idProduct `0x88C5` |
| Device release | `bcdDevice 0x0160` (rev 1.60), `bcdUSB 0x0200` |
| Serial | `000483` |
| USB class | `0xEF` (Miscellaneous), UAC2 (`bInterfaceProtocol 0x20`) |
| USB stack / firmware | Thesycon Systemsoftware & Consulting GmbH |
| Link speed | **USB High-Speed, 480 Mbps** |
| Host OS (failing) | FreeBSD 15.1-RC1 (GENERIC, amd64), `uaudio(4)` / `snd_uaudio.ko` |
| Host controller | Intel Sunrise Point-LP xHCI (`usbus0`, single controller) |
| Player | Music Player Daemon 0.24.12, OSS output to `/dev/dsp0`, bit-perfect |
| Host OS (working) | Linux (ALSA `snd-usb-audio`) — 44.1 kHz family plays perfectly |
| Reference DAC (working on FreeBSD) | Cambridge Audio DacMagic 100 (USB Full-Speed, 24-bit max, **no capture interface**) — no flicker at any rate |

---

## Observed behaviour

### Symptom
- **44.1 kHz family:** DAC display flickers play/idle continuously; audible
  dropouts. Reproducible on every track.
- **48 kHz family:** stable, perfect playback.

### The host side is healthy — the DAC is the one dropping lock
While the 44.1 kHz flicker is happening, FreeBSD's playback channel is in a
**perfectly healthy, steady streaming state**. From `/dev/sndstat` (verbose),
during 44.1 kHz playback:

```
[dsp0.play.0]: spd 44100, fmt 0x00201000, flags 0x2000014c, pid (musicpd)
        interrupts 3746, underruns 0, feed 3745, ready 128248
        [b:5648/2824/2|bs:131072/16384/8]
        channel flags=0x2000014c<RUNNING,TRIGGERED,NBIO,BUSY,BITPERFECT>
        {userland} -> feeder_root(0x00201000) -> {hardware}
```

Key points:
- `interrupts` increment steadily, `underruns 0`, ring buffer full
  (`ready 128248` of `131072`). The host is delivering isochronous frames
  without a single gap.
- The channel never leaves `RUNNING`. **FreeBSD does not stop or restart the
  stream** — yet the *device* keeps losing lock.

This rules out host-side buffer starvation. The repeated re-lock is happening
**inside the DAC**, while it is being fed a continuous, gap-free isochronous
stream.

### Rate is the only variable that matters
The flicker is governed **solely by the sample-rate family**. Forcing the player
to resample to 48 kHz eliminates it instantly:

```
[dsp0.play.0]: spd 48000, fmt 0x00201000, ...
        interrupts ..., underruns 0, ...
```

→ rock-solid playback. Switching back to a 44.1 kHz-family rate brings the
flicker straight back.

---

## USB descriptor analysis (relevant excerpts)

The device exposes a UAC2 configuration with the following streaming
characteristics (from `usbconfig dump_curr_config_desc`).

### Playback interface (Interface 1) — alternate settings

| Alt | `bSubslotSize` | `bBitResolution` | `bmFormats` | Meaning |
|-----|---------------|------------------|-------------|---------|
| 1 | 4 | 24 (`0x18`) | `0x00000001` (PCM) | 24-bit in 32-bit slot |
| 2 | 2 | 16 (`0x10`) | `0x00000001` (PCM) | 16-bit PCM |
| 3 | 4 | 32 (`0x20`) | `0x00000001` (PCM) | 32-bit PCM |
| 4 | 4 | 32 (`0x20`) | `0x80000000` (RAW/DSD) | 32-bit raw (DSD) |

### Streaming endpoints (all alt settings)
- **OUT `0x01`:** `bmAttributes 0x05` → **Asynchronous Isochronous**,
  `bInterval 1` (every 125 µs micro-frame at High-Speed),
  `wMaxPacketSize 0x0188` (392 bytes) for the 32-bit alts.
- **IN `0x81`:** Isochronous **feedback endpoint**, `wMaxPacketSize 4`,
  `bInterval 4` (1 ms). At High-Speed the feedback value is Q16.16.

### Clock topology
- A single **Clock Source** entity (`bClockID 0x29`, internal programmable,
  `bmControls 0x07` → frequency host-programmable + validity) feeding a
  **Clock Selector** (`bClockID 0x28`). This one programmable clock is **shared
  between the playback and capture interfaces**.

### Capture interface (Interface 2)
- The device also exposes a **capture/record stream**, whose default
  (`(selected)`) rate enumerates at **the top of the 48 kHz family**.
  The Cambridge DacMagic 100 (which works on FreeBSD) has **no** capture
  interface.

### How FreeBSD enumerates it
`uaudio(4)` collapses the playback formats to a single 32-bit representation per
rate and selects 384000 Hz / 32-bit as the device default:

```
uaudio0: Play[0]:   384000 Hz, 2 ch, 32-bit S-LE PCM format, 2x8ms buffer. (selected)
uaudio0: Play[0]:   ... 352800 / 192000 / 176400 / 96000 / 88200 / 48000 / 44100 Hz (all 32-bit)
uaudio0: Record[0]: 384000 Hz, 2 ch, 32-bit S-LE PCM ... (selected)   ← shared-clock capture stream
```

Note both directions advertise both rate families against the single shared
clock.

---

## Host-side mitigations attempted (FreeBSD) — none fix the 44.1 kHz flicker

| Change | Result |
|--------|--------|
| MPD `format "*:24:*"` / `"*:16:*"` | No change to wire format. Bit-perfect OSS pins the channel to the hardware's 32-bit format; MPD's conversion is host-side only. Flicker unchanged. |
| `dev.pcm.0.bitperfect=0` | Adds a software volume feeder but the device still streams S32_LE (32-bit). Flicker unchanged. |
| `hw.usb.uaudio.default_bits=24` / `=16` (with driver reload) | **Ignored by `uaudio`** — device still streams 32-bit. |
| `hw.usb.uaudio.buffer_ms` | Already at the maximum allowed value (8; valid range 1–8). No additional buffering available. Flicker unchanged. |
| **Resample to 48 kHz family** | **Fixes it completely.** |

Conclusion: **no host-side format / bit-depth / buffer setting affects the
44.1 kHz flicker.** Only changing the sample-rate *family* does. This points at
the device's behaviour on the 44.1 kHz clock domain rather than at the host's
data delivery (which is verifiably gap-free).

---

## Technical analysis

The decisive facts are:

1. Host delivery is continuous and gap-free (`underruns 0`, channel stays
   `RUNNING`) — yet the DAC repeatedly drops streaming lock.
2. The fault is strictly **sample-rate-family-dependent**: 44.1 kHz family
   fails, 48 kHz family is perfect.
3. The **same hardware/cable/host works perfectly on Linux** for the 44.1 kHz
   family.

Most DACs derive the two rate families from two different master clocks
(e.g. 22.5792 MHz for the 44.1 k family, 24.576 MHz for the 48 k family). The
evidence is consistent with a problem that only manifests when the device is
asked to operate on its **44.1 kHz master-clock domain under FreeBSD's
`uaudio` driver**. Candidate mechanisms, for the manufacturer to evaluate:

1. **Clock-source switch handling / settle time (most likely).**
   UAC2 sets the rate via `SET_CUR` on `CS_SAM_FREQ_CONTROL` of the Clock
   Source entity (`0x29`). FreeBSD and Linux differ in the exact ordering and
   timing of `SET_INTERFACE` (alt-setting selection) versus the clock
   `SET_CUR`, and in whether/how long they poll the clock-validity control
   before streaming. If the device needs additional settle/relock time when
   switching **into** the 44.1 kHz domain (PLL/crystal change), and FreeBSD
   starts isochronous transfers before the clock is stably locked, the device
   would repeatedly invalidate and re-acquire lock — exactly the observed
   flicker. Linux's longer/different sequencing would mask it.

2. **Asynchronous feedback behaviour on the 44.1 kHz domain.**
   The OUT endpoint is async; the device drives the host's per-micro-frame
   sample count through the Q16.16 feedback endpoint (`0x81`). If the feedback
   value reported for 44.1 kHz-family rates differs in scaling/validity from the
   48 kHz family, the device's own input FIFO could oscillate and trigger
   re-lock — even though the host reports no underruns (the host is simply
   sending exactly what it computed). Please confirm the feedback encoding and
   timing are identical across both rate families.

3. **Shared clock contention with the always-present 48 kHz capture stream.**
   A single programmable clock (`0x29`) feeds **both** the playback and the
   capture interfaces, and the capture stream enumerates on the 48 kHz family.
   When playback selects a 44.1 kHz-family rate while the capture endpoint's
   context remains on the 48 kHz family, the firmware may experience
   clock-domain contention and continually re-lock. This is consistent with
   48 kHz playback being stable (both directions then agree on the family) and
   with the contrast against the DacMagic 100, which **has no capture
   interface** and never shows the problem on FreeBSD. Is there a firmware
   option to disable the capture interface, or to force the capture clock to
   follow the active playback family?

4. **Descriptor note (not the root cause, but worth flagging).**
   Playback alt-settings 3 (32-bit PCM) and 4 (32-bit RAW/DSD) carry
   **identical Type-I `FORMAT_TYPE` descriptors** (`bSubslotSize 4`,
   `bBitResolution 32`) and differ only in the `AS_GENERAL` `bmFormats` field
   (`0x00000001` PCM vs `0x80000000` RAW). Hosts that match a requested format
   by subslot size + bit resolution cannot distinguish the two from the
   `FORMAT_TYPE` descriptor alone. FreeBSD always selects 32-bit here. This is
   not rate-dependent and so is unlikely to cause the flicker, but the
   ambiguity is a descriptor-design risk for some drivers.

The strongest single hypothesis is **(1)**, optionally compounded by **(3)**:
a 44.1 kHz clock-domain relock that FreeBSD's `uaudio` does not wait out, which
Linux's `snd-usb-audio` does.

---

## Information that would help the manufacturer

- Expected host sequence and timing for switching the Clock Source to the
  44.1 kHz family: required settle time, whether the host must poll the
  clock-validity control before starting isochronous transfers, and the
  expected ordering of `SET_INTERFACE` vs. clock `SET_CUR`.
- Confirmation that the asynchronous feedback value encoding/scaling and
  cadence are identical for the 44.1 kHz and 48 kHz families.
- Whether the capture interface and its clock can be disabled or forced to
  follow the active playback rate family.
- Any known FreeBSD / `uaudio` interoperability notes for this firmware.

## Reproduction (concise)

1. FreeBSD 15.1, `uaudio(4)`, OKTO DAC8 on a High-Speed USB port.
2. Play bit-perfect 44.1 kHz audio to `/dev/dsp0` → DAC display flickers
   play/idle continuously; audible dropouts. `sndstat` shows `RUNNING`,
   `underruns 0`.
3. Resample/play 48 kHz → stable, perfect.
4. Boot Linux on the same machine, same cable/port → 44.1 kHz plays perfectly.

---

## Current workaround in use

Resample playback to a 48 kHz-family rate before sending it to the DAC (MPD
`format` on the OSS output). Stable, but not bit-perfect for 44.1 kHz-family
source material.

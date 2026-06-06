# FreeBSD `uaudio(4)` patch — OKTO DAC8 STEREO 44.1 kHz fix

Local workaround kept in-tree **while waiting for an official FreeBSD fix.**
See [`FreeBSD-uaudio-shared-clock-bug.md`](FreeBSD-uaudio-shared-clock-bug.md)
for the full root-cause analysis and instructions for filing the upstream bug.

## What it fixes

The OKTO RESEARCH DAC8 STEREO (USB `0x152a:0x88c5`) drops/re-acquires USB
streaming lock continuously on the **44.1 kHz rate family** (44.1/88.2/176.4/
352.8 kHz) on FreeBSD, while the 48 kHz family is fine. Root cause: the device
exposes one UAC2 **Clock Source shared between playback and capture**, and
`uaudio(4)` lets the idle capture channel reprogram that clock to 48 kHz,
clobbering the active playback rate. (Details in the bug-report doc.)

This patch makes `uaudio` **drop the (vestigial — the DAC8 has no analog inputs)
capture interface for this device**, so the shared clock follows playback.
Result: **bit-perfect 44.1 kHz, stable lock, no flicker.**

> This is a deliberately narrow, device-gated workaround — **not** the fix to
> propose upstream. The proper fix is general (an idle/secondary stream must not
> reprogram a shared clock); see the bug-report doc.

## Built/tested environment

- FreeBSD **15.1-RC1**, amd64, `GENERIC` (`releng/15.1-n283533`)
- `snd_uaudio.ko` here is built **with `USB_DEBUG`** (restores the
  `hw.usb.uaudio.debug` sysctl + DPRINTF tracing, matching stock GENERIC).
- The prebuilt `snd_uaudio.ko` is **ABI-specific to that kernel** — rebuild from
  the patches after any kernel update.

## Contents

| File | Purpose |
|------|---------|
| `uaudio.c.patch` | Source change to `sys/dev/sound/usb/uaudio.c` (the device-gated capture-disable). |
| `Makefile.patch` | Adds `CFLAGS+=-DUSB_DEBUG` to the module Makefile. |
| `snd_uaudio.ko` | Prebuilt module (patch + `USB_DEBUG`) for the environment above. |
| `FreeBSD-uaudio-shared-clock-bug.md` | Full analysis + upstream bug-filing instructions. |

## Apply from source and rebuild

```sh
cd /usr/src
patch -p1 < /path/to/uaudio.c.patch
patch -p1 < /path/to/Makefile.patch

cd /usr/src/sys/modules/sound/driver/uaudio
make clean && make
# -> /usr/obj/usr/src/amd64.amd64/sys/modules/sound/driver/uaudio/snd_uaudio.ko
```

## Install (either freshly built or the prebuilt `snd_uaudio.ko`)

```sh
# back up the stock module once (if not already done)
sudo cp -n /boot/kernel/snd_uaudio.ko /boot/kernel/snd_uaudio.ko.orig

sudo service musicpd stop                 # release /dev/dsp0
sudo cp snd_uaudio.ko /boot/kernel/snd_uaudio.ko
sudo kldunload snd_uaudio                 # devd auto-reloads from /boot/kernel
UG=$(usbconfig | awk '/DAC8STEREO/{print $1}' | tr -d ':')
sudo usbconfig -d "$UG" reset             # clean re-enumeration
sudo sysctl -f /etc/sysctl.conf           # reload resets buffer_ms -> restore baseline
sudo service musicpd start
```

Verify:
```sh
cat /dev/sndstat | grep pcm0              # expect: pcm0: <OKTO...> (play)   <- play-only
sysctl hw.usb.uaudio.debug                # exists (USB_DEBUG build)
```

## Revert to stock

```sh
sudo cp /boot/kernel/snd_uaudio.ko.orig /boot/kernel/snd_uaudio.ko
sudo kldunload snd_uaudio && sudo kldload snd_uaudio
```

## Persistence / upgrade caveat

The module lives in `/boot/kernel/snd_uaudio.ko`, so it **survives reboot**
(loaded by name via `devmatch`/`devd` on device attach). However
`freebsd-update` or `make installkernel` (any OS/kernel update) **overwrites it
with the stock module** — rebuild + reinstall from these patches afterwards.
Once the official fix lands upstream, this whole directory can be retired.

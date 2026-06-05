# Current configuration (2025.09.23)

## Geometry

- 120cm from front wall
- sofa at blue marks (see notebook for details)

## Filters

v.1.5.0 with two flavours

1. with max +2dB boost, peak correction with inversion, crossover correction (DRC-120.blue/120-blue-with-inversion+2dB.mdat)

2. with no boost, peak correction with inversion, crossover correction (DRC-120.blue/120-blue-with-inversion.mdat)

Revised crossover files (used in rephase): DRC-120.blue/ LR-EP-psy.txt , LR-EP-unsmoothed.txt, X801.rephase, X801.wav


### configuration

LF.0.raw -> 120.blue/FLX+0dB-192k.raw
RF.0.raw -> 120.blue/FRX+0dB-192k.raw
LF.1.raw -> 120.blue/FLX+2dB-192k.raw
RF.1.raw -> 120.blue/FRX+2dB-192k.raw



## Geometry 

- 120cm from front wall
- sofa at P6 (mic at 306cm from loudspeakers 390 from front wall)

## Filters

### v. 1.1.1 2024.11.27

- Low shelf filter has now a slope of -12dB/octave. 1.1.0 version had a (mistakenly?) -6dB/octave slope. The result leads to an improved clarity in the lowest region (< 80Hz).
- Low shelf filter cutoff at 44.50 Hz  Shape Butterworth  Slope 12 dB/oct
- Mid band EQ now has an effect compared to 1.1.0. 10ms windowing applied before EQ-ing. The bump between 300 and 700 is now tamed.

### v. 1.1.0  2024.11.25 and 2024.11.26

#### Files

1. 120cm.VBALS3dB+MF.correction.mdat
2. 2024.11.25-FVBA-LS3dB.mdat

##### Features

- crossover filters linearization (RePhase)
- no additional phase correction
- Virtual bass array filters with delayed impulse (1st mode: 55.15, second 110.3) and +3dB low shelf filter EQ
- corrective EQ until 220Hz
- corrective EQ from 221 to 693Hz (no motivation for 693, it happened, idea was to set upper limit to 700Hz) after windowing L and R to 10ms (343/3.06, being 3.06 approx speaker distance from listening position)



### files:

- 120cm.VBALS3dB+MF.correction.mdat

![Amplitude: current filter vs uncorrected](doc/current.amplitude.png)

![Phase: current filter vs uncorrected](doc/current.phase.png)

![ETC: current impulse response vs uncorrected](doc/current.impulse.png)

![ETC: current filter vs uncorrected](doc/current.etc.png)

![Clarity [C80]: current filter vs uncorrected](doc/current.clarity.c80.png)

# Description

Configuration files, scripts, filters (raw format), ... for brutefir under Linux. 

Designed and generated from one or more of the DRC-xxx github.com/delleceste folders

# Top level directory *.conf files

The top level directory brutefir-XY.conf files are brutefir configuration files.
Each one *shall load only one brutefir filter*
XY identifies the *name* of the filter/configuration, and it is passed to the *scripts/drc.sh* script as parameter so that brutefir is launched with *brutefir-XY.conf* configuration file.
The parameter *off* is reserved and used by *scripts/drc.sh* to stop the brutefir process.

## Examples
- *brutefir-current.conf*, launched with *drc.sh current*, script pointing to the current (latest) *default* configuration
- *brutefir-last.1.conf*, second last configuration (for comparison purposes, optional)
- *brutefir-last.2.conf*, third last configuration (for comparison purposes, optional)

### Additional config files for flavors different than default

Other brutefir-XY.conf can be optionally added (to offer flavors of different corrections / equalizations).

#### Note:

Filters used in additional brutefir-XY.conf shall reside within specific subfolders, possibly self describing, and shall not clutter the *filters/* top level directory

# The filters/ directory and the symlinks to the current default filter

Contains the filters, each under a directory named after the speaker distance from the front wall. For example, a dir named *120* shall contain filters
designed for speaker placement at 120cm from the front wall. Further documentation shall define other distances, such as the listening position.

## Symlinks to the default filter currently in use

To simplify and minimize editing the brutefir configuration file, two symbolic links:

- LF.raw  (Left Filter)
- RF.raw  (Right Filter)

shall point to the *.raw* filter in use for the *current* configuration.

#  The old.pos/ directory
Configuration files referring to older speaker / listening positions shall be moved here to avoid cluttering the main directory

# scripts/headroom_calc.py

Calculates the minimum `attenuation:` value to set in each brutefir `.conf` file for a given set of filter files, in order to prevent clipping while maximising dynamics.

## How it works

brutefir processes audio entirely in float64 (effectively infinite dynamic range).
The risk of clipping arises only at the output boundary when the filter has gain > 0 dB at some frequency.

For each filter file the script:
1. Reads the raw impulse response samples (supports `FLOAT64_LE` / `S32_LE` formats)
2. Computes the FFT — each bin gives the filter's complex gain at that frequency
3. Takes `max |FFT(h)|` — the worst-case gain across all frequencies
4. Converts to dB: `headroom = 20 × log10(peak_gain)`
5. Adds a configurable safety margin (default 1 dB) and rounds up to one decimal place

Because brutefir applies **one `attenuation:` value per coeff block to both channels**, the script groups filters into L/R pairs and uses the channel with the higher peak gain to determine the pair's attenuation.

Note: minimising attenuation does **not** improve audio quality. In float64 attenuation is lossless; the only goal is to avoid clipping.

## Usage

```bash
python3 scripts/headroom_calc.py
```

Edit the `FILTER_PAIRS` list at the top of the script to add or change filter files and their formats.
Edit `SAFETY_MARGIN_DB` to adjust the margin (default: 1.0 dB).

## Results for filters/120.blue

Output of `headroom_calc.py` as of v1.5.0:

```
Pair                 Channel file                                      Peak gain Limiting ch  Suggested
──────────────────── ────────────────────────────────────────────────       (dB)            atten (dB)
+0dB float64         FLX+0dB-192k_sox_upsample_float64.raw                +1.071   ← limits        2.1
                     FRX+0dB-192k_sox_upsample_float64.raw                -0.038

+2dB float64         FLX+2dB-192k_sox_upsample_float64.raw                +3.060   ← limits        4.1
                     FRX+2dB-192k_sox_upsample_float64.raw                +1.954

+2dB trimmed S32     FLX+2dB-trimmed-192k.raw                             +3.191   ← limits        4.2
                     FRX+2dB-trimmed-192k.raw                             +2.137

Safety margin applied: 1.0 dB
```

The left channel limits in all pairs. Set `attenuation:` in the `.conf` file as follows:

| Filter pair | `attenuation:` (both channels) |
|---|---|
| `+0dB` float64 | **2.1** |
| `+2dB` float64 | **4.1** |
| `+2dB` trimmed S32 | **4.2** |

# The drc.sh script

The *drc.sh* Bash script shall be located in the main folder. It starts the *brutefir* convolution engine and uses `/usr/bin/env bash` so it works with Bash in `/usr/bin` on Linux and `/usr/local/bin` on FreeBSD.
Accepts one parameter, e.g. *current*. Calls *brutefir brutefir-current.conf* (the current configuration)
If the parameter equals *off*, brutefir is stopped.

Additionally, the script calls *mpc* (MPD control application) so that the audio device in *MPD* is switched to the *loopback* device targeted by brutefir or to the native device (if the parameter is *off*)

## MPD native DRC output format

`mpd/musicpd.conf` has a single native DRC output named `DRC-native`.  It uses:

```conf
format "*:*:*"
```

MPD's `format` setting is `sample_rate:bits:channels`.  An asterisk means that
the corresponding attribute is not enforced, so `*:*:*` tells MPD not to force
sample rate, bit depth, or channel count.  This is intentional: native DRC mode
requires selecting the `drc.sh` rate that matches the source track, while MPD
passes the source format through unchanged.

The separate `DRC-resamp` output keeps `format "192000:24:2"` because that mode
explicitly asks MPD to resample everything to 192 kHz.

# The doc/ directory
It shall contain at least two plots (PNG format), each one with two curves: uncorrected and corrected:
- current.amplitude.png: amplitude
- current.phase.png: phase 

# USB DAC hotplug automation

Plugging in the USB DAC automatically starts brutefir and switches MPD to the DRC output.
This is implemented with a udev rule and two systemd system services.

## Event chain

```
USB DAC plugged in
  └─ udev: ACTION==add, SUBSYSTEM==sound, KERNEL==controlC*, SUBSYSTEMS==usb
       └─ SYSTEMD_WANTS=drc-usb-audio.service  (no-op if already active)
            └─ systemd starts drc-usb-audio.service
                 ├─ Wants=brutefir-drc.service  →  brutefir starts (own cgroup)
                 └─ ExecStart: mpc switches MPD output to DAC+DRC (output 3)

USB DAC unplugged
  └─ udev: ACTION==remove, SUBSYSTEM==sound, KERNEL==controlC*, SUBSYSTEMS==usb
       └─ RUN: systemctl stop drc-usb-audio.service
            ├─ ExecStop: mpc switches MPD back to output 1
            └─ PropagatesStopTo=brutefir-drc.service  →  brutefir stops
```

`RemainAfterExit=yes` on `drc-usb-audio.service` prevents the multiple `controlC*` add
events from a single plug-in from starting duplicate brutefir instances. The `remove` rule
resets the service to inactive so the next plug-in works correctly.

## Files

| File | Installed to | Purpose |
|---|---|---|
| `99-usb-audio-drc.rules` | `/etc/udev/rules.d/` | udev rule: triggers the service on DAC plug-in |
| `etc/systemd/system/brutefir-drc.service` | `/etc/systemd/system/` | Manages the brutefir process |
| `etc/systemd/system/drc-usb-audio.service` | `/etc/systemd/system/` | Switches MPD output; declares dependency on brutefir-drc |

## The udev rule (`99-usb-audio-drc.rules`)

```
ACTION=="add", SUBSYSTEM=="sound", KERNEL=="controlC*", SUBSYSTEMS=="usb",
    TAG+="systemd", ENV{SYSTEMD_WANTS}="drc-usb-audio.service"
```

- Matches any USB sound card control device (`controlC*`), regardless of DAC model.
- `TAG+="systemd"` hands the event to systemd.
- `SYSTEMD_WANTS` tells systemd to start `drc-usb-audio.service` if it is not already active.

## Why two service units

A single `Type=oneshot` service that launches brutefir and exits would have brutefir killed
by systemd when the service's cgroup is cleaned up. `KillMode=none` avoids that but is
deprecated. The correct solution is to run brutefir in its **own** service unit with its own
cgroup, so systemd tracks and manages it independently.

**`brutefir-drc.service`** — `Type=simple`, runs brutefir in the foreground (no `-daemon`
flag). systemd owns its full lifecycle: start, stop, and restart. The process stays alive
as long as this unit is active.

**`drc-usb-audio.service`** — `Type=oneshot` with `RemainAfterExit=yes`, triggered by udev.
Declares `Wants=brutefir-drc.service` so systemd starts brutefir-drc automatically, then
waits 1 s for brutefir to initialise (`ExecStartPre=/bin/sleep 1`) before switching MPD
outputs. `RemainAfterExit=yes` keeps the service "active" after ExecStart completes, so
repeated udev events (one USB device generates several `controlC*` events) are ignored and
do not launch additional brutefir instances.

## Installation

Use the Makefile at the root of the repository:

```bash
make install          # copy all files and reload udev + systemd
make install-systemd  # copy service files and reload systemd only
make install-udev     # copy udev rule and reload udev only
```

`make install` requires sudo (prompted once per target that needs it).

## Manual control

The two units are linked: stopping `drc-usb-audio.service` also stops `brutefir-drc.service`
(via `PartOf=`) and switches MPD back to the direct output (via `ExecStop`). This is the
recommended way to stop everything cleanly.

```bash
# Stop DRC completely (stops brutefir + switches MPD back to output 1)
sudo systemctl stop drc-usb-audio.service

# Start DRC manually (starts brutefir + switches MPD to output 3)
sudo systemctl start drc-usb-audio.service

# Stop/start brutefir alone (MPD output is not changed)
sudo systemctl stop  brutefir-drc.service
sudo systemctl start brutefir-drc.service

# Check status
systemctl status brutefir-drc.service
systemctl status drc-usb-audio.service

# Follow logs
journalctl -fu brutefir-drc.service
journalctl -fu drc-usb-audio.service
```

`drc.sh` continues to work for manual invocation outside of systemd (it starts brutefir
with `-daemon` directly and switches MPD outputs in one step).

## User ID note

`drc-usb-audio.service` sets `XDG_RUNTIME_DIR=/run/user/1001` (giacomo's UID).
If the UID changes, update that value in the service file and re-run `make install-systemd`.

## FreeBSD rc.d scripts

FreeBSD equivalents are provided under `etc/rc.d/FreeBSD/`, with an optional `devd`
rule under `etc/devd/FreeBSD/`.

| File | Installed to | Purpose |
|---|---|---|
| `etc/rc.d/FreeBSD/brutefir_drc` | `/usr/local/etc/rc.d/` | Manages the BruteFIR process |
| `etc/rc.d/FreeBSD/drc_usb_audio` | `/usr/local/etc/rc.d/` | Starts/stops BruteFIR and switches MPD outputs |
| `etc/devd/FreeBSD/usb-audio-drc.conf` | `/usr/local/etc/devd/` | Triggers routing on USB audio attach/detach |

Install on FreeBSD with:

```sh
make install-freebsd
```

The `devd` rule calls `service ... onestart/onestop`, so no `rc.conf` enable flags
are required for hotplug operation. Use `/etc/rc.conf` for local overrides; the
defaults match the Linux service files:

```sh
brutefir_drc_user="giacomo"
brutefir_drc_conf="/home/giacomo/DRC/brutefir-conf/brutefir-120.blue+0dB.conf"
drc_usb_audio_start_output="3"
drc_usb_audio_stop_output="1"
drc_usb_audio_mpd_port="6600"
```

If you want either service to start at boot independently of USB hotplug, also set
the corresponding enable flag:

```sh
brutefir_drc_enable="YES"
drc_usb_audio_enable="YES"
```

Manual control:

```sh
service drc_usb_audio onestart  # start BruteFIR + switch MPD to output 3
service drc_usb_audio onestop   # switch MPD to output 1 + stop BruteFIR
service brutefir_drc onestart   # start BruteFIR only
service brutefir_drc onestop    # stop BruteFIR only
```

The `devd` attach rule matches USB audio interface class `0x01`. The detach rule
stops DRC on USB device removal; add DAC-specific `vendor`/`product` matches if the
host has other USB devices whose removal should not stop DRC.

# scripts/REW2raw.sh

Converts a REW-exported WAV impulse response to a brutefir-ready raw float64 file,
resampling to a target sample rate (default: 192 kHz).

The input files are impulse-response FIR filters. For this reason the conversion
does **not** peak-normalise the filter. Peak normalisation would make the result
depend on the largest sample in each channel, including interpolation overshoot
introduced by resampling, and would therefore alter the intended filter gain.

Instead, after resampling, the script applies one deterministic FIR coefficient
scale:

```
scale = input_sample_rate / target_sample_rate
gain_db = 20 * log10(scale)
```

This gain depends only on the sample-rate conversion ratio. It does not depend on
the absolute peak level of the filter, and it is the same for left and right
channels when both source WAVs have the same sample rate.

Theory/source: Julius O. Smith's *Physical Audio Signal Processing* writes that
sampling an impulse response can be expressed as `gamma(t) -> T gamma(nT) ->
gamma(n)`, where `T` is the sampling period. Since `T = 1/Fs`, converting FIR
coefficients from `Fs_source` to `Fs_target` requires:

```
scale = T_target / T_source = Fs_source / Fs_target
```

Reference: https://www.dsprelated.com/freebooks/pasp/Sampling_Impulse_Response.html

Examples for REW exports at 48 kHz:

| Target rate | Scale | Gain |
|---|---:|---:|
| 44100 | 1.0884353741 | +0.73605296 dB |
| 48000 | 1.0 | 0.00000000 dB |
| 96000 | 0.5 | -6.02059991 dB |
| 192000 | 0.25 | -12.04119983 dB |

The printed peak values are diagnostics only. They are useful to inspect clipping
risk and resampling behaviour, but they do not affect the applied gain.

## Resampling quality

The SoX `rate` step uses:

| Flag | Effect |
|------|--------|
| `-v` | Very high quality: band-limited interpolation, 175 dB noise rejection |
| `-L` | Linear phase: preserves the filter's own phase response |
| `-s` | Steep filter: 99% pass-band, keeps near-Nyquist content |
| `-b 64 -e floating-point` | 64-bit float intermediate file, no precision loss before gain stage |
| `-L -t raw -e floating-point -b 64` | final output format: `FLOAT64_LE` raw |

## Usage

```bash
scripts/REW2raw.sh [options] <in.wav> [out.raw|out.wav] [raw|wav] [sample_rate]
```

All arguments after `in.wav` are optional.

Options:

| Option | Meaning |
|---|---|
| `--exact-output` | write exactly the output filename supplied by the caller |
| `--no-keep-intermediate` | remove the temporary float64 WAV after conversion |
| `--intermediate-dir DIR` | write the intermediate float64 WAV in `DIR` |

## Examples

**Explicit output name:**

```bash
scripts/REW2raw.sh FL-REW.wav filters/120.blue/FL-192k.raw
# writes filters/120.blue/FL-192k_sox_upsample_float64.raw
```

By default, `REW2raw.sh` inserts `_sox_upsample_float64` before the output
extension. Use `--exact-output` when the caller needs a stable filename such as
`L.raw` or `R.raw`.

**Exact output name, useful from wrapper scripts:**

```bash
scripts/REW2raw.sh --exact-output --no-keep-intermediate \
  filters/120.blue/rew/FLX-trimmed-48k.wav \
  filters/120.blue/96000/L.raw \
  raw 96000
```

**Keep final output as WAV (e.g. for inspection in REW or Audacity):**

```bash
scripts/REW2raw.sh FL-REW.wav FL-192k.wav wav
```

**Custom sample rate (e.g. 96 kHz):**

```bash
scripts/REW2raw.sh FL-REW.wav FL-96k.raw raw 96000
```

# scripts/REW2raw-all-rates.sh

Generates a stereo pair (`L.raw`, `R.raw`) for every numeric sample-rate directory
directly below an output filter root.

For the current `filters/120.blue` layout:

```text
filters/120.blue/
  44100/
  48000/
  88200/
  96000/
  192000/
  rew/
```

the script processes only the numeric directories and ignores `rew/`.

## Usage

```bash
scripts/REW2raw-all-rates.sh \
  -L filters/120.blue/rew/FLX-trimmed-48k.wav \
  -R filters/120.blue/rew/FRX-trimmed-48k.wav \
  -o filters/120.blue
```

Options:

| Option | Meaning |
|---|---|
| `-L FILE` | left REW-exported WAV impulse response |
| `-R FILE` | right REW-exported WAV impulse response |
| `-o DIR` | output root, e.g. `filters/120.blue` |
| `-y` | do not ask before writing each `L.raw` / `R.raw` pair |

For each numeric sample-rate directory, the script writes:

| File | Meaning |
|---|---|
| `L.raw` | left filter, raw `FLOAT64_LE` |
| `R.raw` | right filter, raw `FLOAT64_LE` |
| `sox.txt` | full conversion log: wrapper command, `REW2raw.sh` calls, SoX command lines, SoX output and measured stats |

Without `-y`, the script asks before writing each rate directory. This is important
when `filters/120.blue/192000` already contains the checked/current filters: answer
`n` for that directory if it must not be overwritten.

If a destination already contains `L.raw` or `R.raw`, the prompt explicitly lists
the existing file(s) and asks for overwrite confirmation. With `-y`, existing
outputs are overwritten automatically, but the script still prints an overwrite
warning before doing so.

After generating filters, run `python3 scripts/headroom_calc.py` to determine the
correct `attenuation:` value for the brutefir `.conf` file. Headroom calculation is
separate from REW-to-RAW conversion: `REW2raw.sh` preserves FIR gain according to
the sample-rate ratio, while `headroom_calc.py` determines the playback attenuation
needed to avoid clipping.

# History and notes

![VBA filter with ALL-PASS phase filter comparison](doc/xtras/FVBA.vs.ALLPASS.md)

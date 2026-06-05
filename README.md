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

# configs/ directory

Per-geometry, per-rate brutefir configuration files live under `configs/<geometry>/`.

Each file sets `sampling_rate`, points to the matching filter files in `filters/<geometry>/<rate>/`,
and is selected automatically by `drc.sh` based on the active geometry and rate.

Variant configs (e.g. `+2dB`) live alongside the default:
`configs/120.blue/brutefir-192000.conf` (default), `configs/120.blue/brutefir-192000+2dB.conf`, etc.

# The filters/ directory

Contains filter raw files under `filters/<geometry>/<rate>/L.raw` and `R.raw`.
Variants live one level deeper: `filters/<geometry>/<rate>/<variant>/L.raw`.

See `FILTERS_AND_DRC.md` for full documentation of the filter layout, REW2raw conversion,
and how to add new rates or geometries.

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

`drc.sh` is the single control point for the DRC pipeline. It uses `/usr/bin/env bash`
so it works with Bash in `/usr/bin` on Linux and `/usr/local/bin` on FreeBSD.

Signature: `drc.sh <rate>|resamp|restore|off [variant]`

- `<rate>` — start brutefir at the given sample rate (44100, 48000, 88200, 96000, 192000);
  restarts virtual_oss at the same rate; switches MPD to `DRC-native`
- `resamp` — restarts everything at 192000 Hz; switches MPD to `DRC-resamp` (MPD resamples)
- `restore` — reads `last_arg` and re-applies the last saved state; falls back to 192000 if
  no active state was saved; used by all service files on start
- `off` — stops brutefir and virtual_oss; switches MPD back to output 1
- `variant` — optional second argument, e.g. `+2dB`, selects an alternate filter set

State is saved to `last_arg` on each successful invocation so `restore` can recover it.
Geometry (speaker position) is hardcoded at the top of the script (`GEOMETRY="120.blue"`).

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
                 └─ ExecStartPre: sleep 1  (USB settle time)
                 └─ ExecStart: drc.sh restore
                      ├─ reads last_arg state file
                      ├─ restarts virtual_oss at saved rate
                      ├─ starts brutefir with saved config
                      └─ switches MPD to saved output (DRC-native or DRC-resamp)

USB DAC unplugged
  └─ udev: ACTION==remove, SUBSYSTEM==sound, KERNEL==controlC*, SUBSYSTEMS==usb
       └─ RUN: systemctl stop drc-usb-audio.service
            └─ ExecStop: drc.sh off
                 ├─ stops brutefir
                 ├─ stops virtual_oss
                 └─ switches MPD back to output 1
```

`RemainAfterExit=yes` on `drc-usb-audio.service` prevents the multiple `controlC*` add
events from a single plug-in from starting duplicate brutefir instances. The `remove` rule
resets the service to inactive so the next plug-in works correctly.

`brutefir-drc.service` provides the same `drc.sh restore` / `drc.sh off` lifecycle for
manual control and optional boot-time startup, without the USB settle delay.

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

Both services use `Type=oneshot` with `RemainAfterExit=yes`. They both call `drc.sh restore`
on start and `drc.sh off` on stop; the only difference is that `drc-usb-audio.service` adds
`ExecStartPre=/bin/sleep 1` to wait for the USB DAC to settle before starting brutefir.

**`brutefir-drc.service`** — for manual control and optional boot-time startup. No delay.
Can be enabled in `/etc/systemd/system/` to start DRC automatically at boot.

**`drc-usb-audio.service`** — triggered by udev on USB DAC plug-in. The 1-second settle
delay avoids starting brutefir before the DAC's OSS device node is available.
`RemainAfterExit=yes` keeps the service "active" after ExecStart completes so repeated
udev events (one USB device generates several `controlC*` events) are ignored and do not
launch additional brutefir instances.

## Installation

Use the Makefile at the root of the repository:

```bash
make install          # copy all files and reload udev + systemd
make install-systemd  # copy service files and reload systemd only
make install-udev     # copy udev rule and reload udev only
```

`make install` requires sudo (prompted once per target that needs it).

## Manual control

```bash
# Stop DRC completely (stops brutefir + virtual_oss + switches MPD back to output 1)
sudo systemctl stop drc-usb-audio.service

# Start DRC (restores last saved rate/variant, or defaults to 192000)
sudo systemctl start drc-usb-audio.service

# Manual DRC control without USB trigger
sudo systemctl start brutefir-drc.service
sudo systemctl stop  brutefir-drc.service

# Check status
systemctl status brutefir-drc.service
systemctl status drc-usb-audio.service

# Follow logs
journalctl -fu brutefir-drc.service
journalctl -fu drc-usb-audio.service
```

`drc.sh` continues to work for manual invocation outside of systemd, including direct
rate/variant selection: `drc.sh 192000`, `drc.sh 192000 +2dB`, `drc.sh resamp`, `drc.sh off`.

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
are required for hotplug operation. Use `/etc/rc.conf` for local overrides:

```sh
brutefir_drc_drcsh="/home/giacomo/DRC/brutefir-conf/drc.sh"
drc_usb_audio_start_delay="1"
```

If you want either service to start at boot independently of USB hotplug, also set
the corresponding enable flag:

```sh
brutefir_drc_enable="YES"
drc_usb_audio_enable="YES"
```

Manual control:

```sh
service drc_usb_audio onestart  # restore last DRC state + switch MPD
service drc_usb_audio onestop   # stop BruteFIR + switch MPD to output 1
service brutefir_drc onestart   # restore last DRC state (no USB settle delay)
service brutefir_drc onestop    # stop BruteFIR + virtual_oss + switch MPD
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

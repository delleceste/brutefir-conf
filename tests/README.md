# Bit-perfect test asset

`bitperfect-test-44100-s32-stereo.wav` — the deterministic signal used to verify
the playback chain (see `../doc/BIT-PERFECT-VERIFICATION.md`).

- Format: **WAV, 32-bit PCM (S32_LE), 2 ch, 44100 Hz, 100000 frames (~2.27 s)**.
- Content: a per-sample counter in the **low 16 bits** — L = `i & 0xFFFF`,
  R = `(i*40503) & 0xFFFF`. This is **near-silent (~−90 dBFS)** yet every sample
  is uniquely determined, so any truncation / dither / volume / resampling shows
  up immediately, and the distinct L/R streams catch a channel swap. The WAV's
  PCM payload is byte-identical to `bitperfect-test-44100-s32-stereo.raw`
  (the `.raw` is just the WAV minus its 44-byte header — the reference for
  byte comparison).

Why a WAV: MPD cannot play headerless raw, so the identical PCM is wrapped in a
header-only WAV. What MPD decodes and outputs equals the `.raw` byte-for-byte.

Regenerate:

```sh
python3 - tests/bitperfect-test-44100-s32-stereo.wav tests/bitperfect-test-44100-s32-stereo.raw 100000 44100 <<'PY'
import sys, struct, wave
wav, raw, n, rate = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
buf = bytearray()
for i in range(n): buf += struct.pack("<ii", i & 0xFFFF, (i*40503) & 0xFFFF)
open(raw, "wb").write(buf)
w = wave.open(wav, "wb"); w.setnchannels(2); w.setsampwidth(4); w.setframerate(rate)
w.writeframes(buf); w.close()
PY
```

Feed it to MPD without the music dir mounted, by adding a local socket and using
a `file://` URL (MPD forbids `file://` over TCP):

```sh
# add a local socket to musicpd.conf, restart, then:
export MPD_HOST=/tmp/mpd.sock
cp tests/bitperfect-test-44100-s32-stereo.wav /tmp/bp.wav && chmod 0644 /tmp/bp.wav
mpc enable only OKTO-DAC
mpc clear && mpc add "file:///tmp/bp.wav" && mpc play
```

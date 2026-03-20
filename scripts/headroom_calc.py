#!/usr/bin/env python3
"""
headroom_calc.py
----------------
Calculates the minimum attenuation (headroom) required in brutefir.conf
for each FIR filter file, to prevent clipping and maximise dynamics.

Principle
---------
brutefir convolves the input audio (max amplitude ±1.0 in float) with the
filter's impulse response h[n].  The worst-case output amplitude at any
given frequency f is:

    |output(f)| = |input(f)| × |H(f)|

where H(f) is the filter's complex frequency response.  For a full-scale
sine at the frequency of maximum gain the output would clip if |H(f)| > 1.

The required headroom in dB is therefore:

    headroom_dB = 20 × log10( max_f |H(f)| )   [only positive values matter]

We obtain H(f) by taking the FFT of the impulse response:
the FFT output at each bin IS H(f) evaluated at that bin's frequency,
so we just take the magnitude and find the maximum.

A practical safety margin of +1 dB is added on top.  The suggested
brutefir `attenuation:` value is then rounded up to one decimal place.
"""

import numpy as np
import os

# ── Configuration ────────────────────────────────────────────────────────────

FILTER_DIR = os.path.join(os.path.dirname(__file__), '..', 'filters', '120.blue')
SAFETY_MARGIN_DB = 1.0   # extra dB added on top of the theoretical minimum

# Map each .raw file to its sample format.
# FLOAT64_LE → numpy dtype '<f8'  (64-bit little-endian float, as written by sox)
# S32_LE     → numpy dtype '<i4'  (32-bit little-endian signed int, as written by REW)
#
# Filters are grouped into L/R pairs: brutefir uses a single `attenuation:` value
# per coeff block, and both channels must share the same value to preserve balance.
# The pair's attenuation is therefore driven by whichever channel needs more headroom.
FILTER_PAIRS = [
    # (left_file, left_dtype, right_file, right_dtype, pair_label)
    (
        'FLX+0dB-192k_sox_upsample_float64.raw', '<f8',
        'FRX+0dB-192k_sox_upsample_float64.raw', '<f8',
        '+0dB float64',
    ),
    (
        'FLX+2dB-192k_sox_upsample_float64.raw', '<f8',
        'FRX+2dB-192k_sox_upsample_float64.raw', '<f8',
        '+2dB float64',
    ),
    (
        'FLX+2dB-trimmed-192k.raw', '<i4',
        'FRX+2dB-trimmed-192k.raw', '<i4',
        '+2dB trimmed S32',
    ),
]

# ── Helpers ──────────────────────────────────────────────────────────────────

def load_filter(path: str, dtype: str) -> np.ndarray:
    """Load raw samples and return them as a normalised float64 array."""

    with open(path, 'rb') as fh:
        raw = fh.read()

    # Parse the bytes into the declared sample type
    samples = np.frombuffer(raw, dtype=dtype)

    if dtype == '<i4':
        # S32_LE: full scale is 2^31.  Divide to bring into the ±1 range
        # that matches the floating-point world brutefir works in.
        samples = samples.astype(np.float64) / (2 ** 31)

    # dtype '<f8' is already in ±1 range (by construction from sox)
    return samples.astype(np.float64)


def peak_gain_db(h: np.ndarray) -> float:
    """
    Return the peak gain of the FIR impulse response h[n] in dB.

    Steps:
      1. FFT of h[n] → H[k]  (complex spectrum, one bin per frequency)
      2. Magnitude |H[k]|    (how much the filter amplifies a sine at that freq)
      3. max over all bins   (worst-case frequency for clipping)
      4. convert to dB       (20×log10 because we're talking amplitude, not power)
    """

    # Use the next power-of-two length for FFT efficiency; zero-padding does
    # not change the result, it just interpolates between existing bins.
    n_fft = 1
    while n_fft < len(h):
        n_fft <<= 1          # shift left = multiply by 2

    # Compute the real FFT (h is real, so we only need the positive half)
    H = np.fft.rfft(h, n=n_fft)

    # Magnitude spectrum: |H[k]| for each frequency bin
    magnitude = np.abs(H)

    # Peak gain across all frequencies (linear scale)
    peak_linear = magnitude.max()

    # Convert to dB.  If peak < 1 the filter actually attenuates everywhere
    # and no correction is needed (return 0); log10 of values ≤ 0 is undefined.
    if peak_linear <= 0:
        return float('-inf')

    return 20.0 * np.log10(peak_linear)


def suggested_attenuation(peak_db: float, margin_db: float) -> float:
    """
    Return the brutefir `attenuation:` value to use.

    brutefir's attenuation is a *positive* number of dB of reduction.
    We only need attenuation when the filter has gain > 0 dB.
    We round up to one decimal place to keep the conf file tidy.
    """
    raw = max(peak_db, 0.0) + margin_db
    # Ceiling to one decimal place
    return round(np.ceil(raw * 10) / 10, 1)


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    col_pair  = 20
    col_ch    = 48
    col_num   = 10

    header = (f"{'Pair':<{col_pair}} {'Channel file':<{col_ch}}"
              f" {'Peak gain':>{col_num}} {'Limiting ch':>{col_num}} {'Suggested':>{col_num}}")
    print(header)
    print(f"{'':─<{col_pair}} {'':─<{col_ch}} {'(dB)':>{col_num}} {'':>{col_num}} {'atten (dB)':>{col_num}}")

    for l_file, l_dtype, r_file, r_dtype, label in FILTER_PAIRS:

        results = {}
        for ch, filename, dtype in [('L', l_file, l_dtype), ('R', r_file, r_dtype)]:
            path = os.path.join(FILTER_DIR, filename)
            if not os.path.exists(path):
                print(f"  {'FILE NOT FOUND: ' + filename}")
                results[ch] = None
                continue
            h = load_filter(path, dtype)
            results[ch] = peak_gain_db(h)

        if None in results.values():
            continue

        peak_l, peak_r = results['L'], results['R']

        # The channel with the higher peak gain determines the attenuation for the pair.
        # Using the other channel's (lower) value would leave the louder one clipping.
        limiting_ch = 'L' if peak_l >= peak_r else 'R'
        peak_pair   = max(peak_l, peak_r)
        suggested   = suggested_attenuation(peak_pair, SAFETY_MARGIN_DB)

        # Print one row per channel, with pair label and suggestion only on first row
        print(f"{label:<{col_pair}} {l_file:<{col_ch}} {peak_l:>+{col_num}.3f}"
              f" {'← limits' if limiting_ch == 'L' else '':>{col_num}} {suggested:>{col_num}.1f}")
        print(f"{'': <{col_pair}} {r_file:<{col_ch}} {peak_r:>+{col_num}.3f}"
              f" {'← limits' if limiting_ch == 'R' else '':>{col_num}}")
        print()

    print(f"Safety margin applied: {SAFETY_MARGIN_DB} dB")
    print("'Suggested atten (dB)' → use this for BOTH channels in brutefir.conf `attenuation:`")
    print("Note: attenuation in brutefir is a gain reduction applied before convolution output;"
          "\n      it is lossless in float64 — only clipping prevention matters, not level optimisation.")


if __name__ == '__main__':
    main()

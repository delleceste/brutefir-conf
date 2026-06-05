#!/usr/bin/env bash
set -euo pipefail

# ── local configuration ───────────────────────────────────────────────────────
POSITION="120.blue"   # speaker geometry / filter set to use

VIRTUAL_OSS_PID=/tmp/virtual_oss.pid
VIRTUAL_OSS_ARGS="-i 8 -C 2 -c 2 -b 32 -s 200ms -f /dev/null -a 0 -d dsp.play -a 0 -l dsp.loop"

usage() {
  echo "Usage: $0 <rate>|resamp|off [variant]"
  echo "  rate     : 44100 | 48000 | 88200 | 96000 | 192000"
  echo "             native mode: select the rate matching the source track;"
  echo "             MPD uses DRC-native format *:*:* and does not resample"
  echo "  resamp   : MPD resamples everything to 192000 Hz"
  echo "  off      : stop brutefir and DRC; enable direct DAC output"
  echo "  variant  : optional filter variant, e.g. +2dB (default: none)"
  echo
  echo "  Position is fixed to: $POSITION"
  echo "  Edit POSITION at the top of this script to change it."
  echo
  echo "Examples:"
  echo "  $0 192000"
  echo "  $0 192000 +2dB"
  echo "  $0 resamp"
  echo "  $0 off"
}

if [ $# -eq 1 ] && [ "$1" = "off" ]; then
  mode="off"
  rate=""
  variant=""
elif [ $# -eq 1 ] || [ $# -eq 2 ]; then
  rate="$1"
  variant="${2:-}"
  if [ "$rate" = "resamp" ]; then
    mode="resamp"
    actual_rate=192000
  else
    mode="normal"
    actual_rate="$rate"
  fi
else
  usage
  exit 1
fi

drc_root="/home/giacomo/DRC"
brutefir_conf_dir="brutefir-conf"
base_dir="$drc_root/$brutefir_conf_dir"

STATE_FILE="$base_dir/last_arg"
process_name="brutefir"

# ── stop brutefir ────────────────────────────────────────────────────────────
if pgrep "$process_name" > /dev/null; then
  echo "stopping brutefir"
  killall "$process_name"
  sleep 1
else
  echo "brutefir not running"
fi

# ── off: re-enable direct DAC, stop virtual_oss ──────────────────────────────
if [ "$mode" = "off" ]; then
  mpc enable only 1
  if [ -f "$VIRTUAL_OSS_PID" ]; then
    echo "stopping virtual_oss"
    sudo kill "$(sudo cat "$VIRTUAL_OSS_PID")" 2>/dev/null || true
    sudo rm -f "$VIRTUAL_OSS_PID"
  fi
  echo "off" > "$STATE_FILE"
  chmod 644 "$STATE_FILE" 2>/dev/null || true
  echo "DRC stopped"
  exit 0
fi

# ── validate config ──────────────────────────────────────────────────────────
conf_file="$base_dir/configs/$POSITION/brutefir-${actual_rate}${variant}.conf"
if [ ! -f "$conf_file" ]; then
  echo "config not found: $conf_file"
  exit 1
fi

# ── restart virtual_oss at the required sample rate ──────────────────────────
if [ -f "$VIRTUAL_OSS_PID" ]; then
  echo "stopping virtual_oss"
  sudo kill "$(sudo cat "$VIRTUAL_OSS_PID")" 2>/dev/null || true
  sudo rm -f "$VIRTUAL_OSS_PID"
  sleep 1
fi
echo "starting virtual_oss at ${actual_rate} Hz"
# shellcheck disable=SC2086
sudo virtual_oss -D "$VIRTUAL_OSS_PID" -r "$actual_rate" $VIRTUAL_OSS_ARGS &
sleep 1

# ── start brutefir ───────────────────────────────────────────────────────────
echo "starting brutefir: $conf_file"
brutefir "$conf_file" -daemon > /tmp/brutefir.out 2>&1
sleep 1

# ── enable the matching MPD output ───────────────────────────────────────────
if [ "$mode" = "resamp" ]; then
  mpd_output="DRC-resamp"
else
  mpd_output="DRC-native"
fi
mpc disable all
mpc enable "$mpd_output"

# ── record state ─────────────────────────────────────────────────────────────
echo "${POSITION} ${rate}${variant:+ ${variant}}" > "$STATE_FILE"
chmod 644 "$STATE_FILE" 2>/dev/null || true

echo "DRC active: position=${POSITION} rate=${rate}${variant:+ variant=${variant}} (MPD output: ${mpd_output})"

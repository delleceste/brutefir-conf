#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 -L left.wav -R right.wav -o output_dir [-y]"
  echo
  echo "Generate brutefir FLOAT64_LE stereo filter pairs for every numeric"
  echo "sample-rate directory directly under output_dir."
  echo
  echo "Options:"
  echo "  -L FILE  left REW-exported WAV impulse response"
  echo "  -R FILE  right REW-exported WAV impulse response"
  echo "  -o DIR   output root, e.g. filters/120.blue"
  echo "  -y       do not ask before writing each L.raw/R.raw pair"
  echo "  -h       show this help"
  echo
  echo "Each numeric directory receives:"
  echo "  L.raw    raw little-endian float64 left filter"
  echo "  R.raw    raw little-endian float64 right filter"
  echo "  sox.txt  REW2raw command lines and full SoX output"
  echo
  echo "FIR scaling theory:"
  echo "  sampled impulse responses use T*h(nT), where T is the sampling period."
  echo "  Therefore scale = T_target/T_source = Fs_source/Fs_target."
}

YES=0
LEFT=""
RIGHT=""
OUT_DIR=""

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED="$(printf '\033[31m')"
  BLUE="$(printf '\033[34m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BOLD="$(printf '\033[1m')"
  RESET="$(printf '\033[0m')"
else
  RED=""
  BLUE=""
  GREEN=""
  YELLOW=""
  BOLD=""
  RESET=""
fi

while getopts ":L:R:o:yh" opt; do
  case "$opt" in
    L) LEFT="$OPTARG" ;;
    R) RIGHT="$OPTARG" ;;
    o) OUT_DIR="$OPTARG" ;;
    y) YES=1 ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Option -$OPTARG requires an argument" >&2
      usage >&2
      exit 1
      ;;
    \?)
      echo "Unknown option: -$OPTARG" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$LEFT" ] || [ -z "$RIGHT" ] || [ -z "$OUT_DIR" ]; then
  usage >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REW2RAW="$SCRIPT_DIR/REW2raw.sh"

if [ ! -x "$REW2RAW" ]; then
  echo "REW2raw script is not executable: $REW2RAW" >&2
  exit 2
fi

if [ ! -f "$LEFT" ]; then
  echo "Left WAV not found: $LEFT" >&2
  exit 2
fi

if [ ! -f "$RIGHT" ]; then
  echo "Right WAV not found: $RIGHT" >&2
  exit 2
fi

if [ ! -d "$OUT_DIR" ]; then
  echo "Output directory not found: $OUT_DIR" >&2
  exit 2
fi

for tool in sox soxi; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "${tool} not found in PATH" >&2
    exit 2
  fi
done

LEFT_SR="$(soxi -r "$LEFT")"
RIGHT_SR="$(soxi -r "$RIGHT")"

if [ -z "$LEFT_SR" ] || [ -z "$RIGHT_SR" ]; then
  echo "Could not determine input sample rate for both channels" >&2
  exit 2
fi

RATES=()
for entry in "$OUT_DIR"/*; do
  [ -e "$entry" ] || continue
  [ -d "$entry" ] || continue
  base="$(basename -- "$entry")"
  if [[ "$base" =~ ^[0-9]+$ ]]; then
    RATES+=("$base")
  fi
done

if [ "${#RATES[@]}" -gt 0 ]; then
  mapfile -t RATES < <(printf '%s\n' "${RATES[@]}" | sort -n)
fi

if [ "${#RATES[@]}" -eq 0 ]; then
  echo "No numeric sample-rate directories found under: $OUT_DIR" >&2
  exit 3
fi

print_cmd() {
  printf '+ NO_COLOR=1'
  printf ' %q' "$@"
  printf '\n'
}

channel_color() {
  case "$1" in
    Left) printf '%s' "$BLUE" ;;
    Right) printf '%s' "$RED" ;;
    *) printf '%s' "$RESET" ;;
  esac
}

color_line() {
  local color="$1"
  local text="$2"
  printf '%s%s%s\n' "$color" "$text" "$RESET"
}

sample_rate_gain_db() {
  local source_sr="$1"
  local target_sr="$2"
  awk -v source_sr="$source_sr" -v target_sr="$target_sr" 'BEGIN{
    printf "%.8f", 20 * (log(source_sr / target_sr) / log(10))
  }'
}

sample_rate_scale() {
  local source_sr="$1"
  local target_sr="$2"
  awk -v source_sr="$source_sr" -v target_sr="$target_sr" 'BEGIN{
    printf "%.10f", source_sr / target_sr
  }'
}

confirm_rate() {
  local rate="$1"
  local dir="$2"
  local left_out="$3"
  local right_out="$4"
  local existing=()

  if [ -e "$left_out" ]; then
    existing+=("$left_out")
  fi

  if [ -e "$right_out" ]; then
    existing+=("$right_out")
  fi

  if [ "$YES" -eq 1 ]; then
    if [ "${#existing[@]}" -gt 0 ]; then
      echo "${YELLOW}Existing output will be overwritten because -y was given:${RESET}"
      printf '  %s\n' "${existing[@]}"
    fi
    return 0
  fi

  if [ "${#existing[@]}" -gt 0 ]; then
    echo "${YELLOW}Destination already contains output file(s):${RESET}"
    printf '  %s\n' "${existing[@]}"
    printf 'Overwrite existing output for %s Hz? [y/N] ' "$rate"
  else
  printf 'Write %s/L.raw and %s/R.raw for %s Hz? [y/N] ' "$dir" "$dir" "$rate"
  fi

  local reply
  if ! read -r reply; then
    echo
    return 1
  fi
  case "$reply" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

run_rew2raw_logged() {
  local label="$1"
  local input="$2"
  local output="$3"
  local rate="$4"
  local color
  color="$(channel_color "$label")"

  echo
  color_line "$color" "== $label channel =="
  {
    print_cmd "$REW2RAW" --exact-output --no-keep-intermediate "$input" "$output" raw "$rate"
    NO_COLOR=1 "$REW2RAW" --exact-output --no-keep-intermediate "$input" "$output" raw "$rate"
  } | while IFS= read -r line; do
    color_line "$color" "$line"
  done
}

echo "REW to brutefir raw generator"
color_line "$BLUE" "Left input : $LEFT (${LEFT_SR} Hz)"
color_line "$RED" "Right input: $RIGHT (${RIGHT_SR} Hz)"
echo "Output root: $OUT_DIR"
echo "Rates      : ${RATES[*]}"
echo
echo "Quality    : SoX rate -v -L -s, float64 processing, FLOAT64_LE raw output"
echo "FIR gain   : input sample rate / target sample rate"
echo "Theory     : sampled impulse response coefficients use T*h(nT)"
echo "Source     : J.O. Smith, Physical Audio Signal Processing, Sampling the Impulse Response"
echo "URL        : https://www.dsprelated.com/freebooks/pasp/Sampling_Impulse_Response.html"
echo

for rate in "${RATES[@]}"; do
  rate_dir="$OUT_DIR/$rate"
  left_out="$rate_dir/L.raw"
  right_out="$rate_dir/R.raw"
  log_out="$rate_dir/sox.txt"
  left_scale="$(sample_rate_scale "$LEFT_SR" "$rate")"
  right_scale="$(sample_rate_scale "$RIGHT_SR" "$rate")"
  left_gain_db="$(sample_rate_gain_db "$LEFT_SR" "$rate")"
  right_gain_db="$(sample_rate_gain_db "$RIGHT_SR" "$rate")"

  echo "---- ${rate} Hz ----"
  echo "Target directory: $rate_dir"
  color_line "$BLUE" "LEFT  scale=${LEFT_SR}/${rate} (${left_scale}), applied sample-rate gain=${left_gain_db} dB"
  color_line "$RED" "RIGHT scale=${RIGHT_SR}/${rate} (${right_scale}), applied sample-rate gain=${right_gain_db} dB"

  if ! confirm_rate "$rate" "$rate_dir" "$left_out" "$right_out"; then
    echo "Skipped ${rate} Hz"
    echo
    continue
  fi

  echo "Writing pair: $left_out / $right_out"
  color_line "$BLUE" "LEFT  -> $left_out"
  color_line "$RED" "RIGHT -> $right_out"
  echo "Log         : $log_out"

  {
    echo "REW2raw all-rates conversion log"
    echo "Date: $(date -Iseconds)"
    echo "Rate: $rate"
    echo "Output directory: $rate_dir"
    color_line "$BLUE" "Left input: $LEFT (${LEFT_SR} Hz)"
    color_line "$RED" "Right input: $RIGHT (${RIGHT_SR} Hz)"
    color_line "$BLUE" "Left output: $left_out"
    color_line "$RED" "Right output: $right_out"
    echo
    echo "Quality flags:"
    echo "  SoX rate -v -L -s"
    echo "  float64 intermediate processing"
    echo "  raw output: FLOAT64_LE"
    echo "  FIR gain: input sample rate / target sample rate"
    echo
    echo "FIR scaling theory:"
    echo "  Quote: Sampling the impulse response can be expressed mathematically as gamma(t) -> T gamma(nT) -> gamma(n)."
    echo "  Source: J.O. Smith, Physical Audio Signal Processing, Sampling the Impulse Response"
    echo "  URL: https://www.dsprelated.com/freebooks/pasp/Sampling_Impulse_Response.html"
    echo "  Since T = 1/Fs, scale = T_target/T_source = Fs_source/Fs_target."
    color_line "$BLUE" "  LEFT  scale=${LEFT_SR}/${rate} (${left_scale}), applied sample-rate gain=${left_gain_db} dB"
    color_line "$RED" "  RIGHT scale=${RIGHT_SR}/${rate} (${right_scale}), applied sample-rate gain=${right_gain_db} dB"
    run_rew2raw_logged "Left" "$LEFT" "$left_out" "$rate"
    run_rew2raw_logged "Right" "$RIGHT" "$right_out" "$rate"
  } >"$log_out" 2>&1

  echo "Done ${rate} Hz"
  echo
done

echo "All selected sample-rate directories processed."

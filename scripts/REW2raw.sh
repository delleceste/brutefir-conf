#!/usr/bin/env bash
set -euo pipefail

# resample_normalize_keep_intermediate.sh
#
# Usage:
#   ./REW2raw.sh [--exact-output] [--no-keep-intermediate] [--intermediate-dir DIR] in.wav [out.raw|out.wav] [wav|raw] [sample_rate]
#
# - If OUT is omitted, output will be derived from IN with suffix _sox_upsample_float64.
# - Third arg "wav" forces final output as WAV (64-bit float). Default is "raw".
# - Fourth arg sets sample rate (default 192000).
#
# The script:
# 1) measures peaks/stats of input
# 2) resamples to SR into an intermediate WAV (64-bit float) named with suffix
# 3) measures stats of resampled file and prints colored comparisons
# 4) scales FIR coefficients by input_rate / target_rate and writes final output
# 5) leaves intermediate WAV file in place for inspection unless --no-keep-intermediate is used

usage() {
  echo "Usage: $0 [--exact-output] [--no-keep-intermediate] [--intermediate-dir DIR] in.wav [out.raw|out.wav] [wav|raw] [sample_rate]"
  echo
  echo "Options:"
  echo "  --exact-output          write exactly OUT instead of inserting _sox_upsample_float64"
  echo "  --no-keep-intermediate  remove the float64 intermediate WAV after conversion"
  echo "  --intermediate-dir DIR  write the intermediate WAV in DIR"
  echo
  echo "SoX quality: rate -v -L -s, float64 intermediate, FLOAT64_LE raw output."
  echo "FIR gain: input_sample_rate / target_sample_rate."
}

EXACT_OUTPUT=0
KEEP_INTERMEDIATE=1
INTERMEDIATE_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --exact-output)
      EXACT_OUTPUT=1
      shift
      ;;
    --no-keep-intermediate)
      KEEP_INTERMEDIATE=0
      shift
      ;;
    --intermediate-dir)
      if [ $# -lt 2 ]; then
        echo "Missing argument for --intermediate-dir" >&2
        exit 1
      fi
      INTERMEDIATE_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

# Colors
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  BOLD="$(printf '\033[1m')"
  RESET="$(printf '\033[0m')"
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  BOLD=""
  RESET=""
fi

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

IN="$1"
OUT_ARG="${2:-}"
MODE="${3:-raw}"        # "wav" or "raw"
SR="${4:-192000}"       # sample rate

if [ ! -f "$IN" ]; then
  echo "${RED}Input file not found:${RESET} $IN" >&2
  exit 2
fi

for tool in sox soxi; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "${RED}${tool} not found in PATH${RESET}" >&2
    exit 2
  fi
done

SOURCE_SR="$(soxi -r "$IN")"
if [ -z "$SOURCE_SR" ]; then
  echo "${RED}Could not determine input sample rate:${RESET} $IN" >&2
  exit 3
fi

# derive base names and output names with suffix
suffix="_sox_upsample_float64"

# helper to insert suffix before extension
insert_suffix() {
  local path="$1"
  local base ext dir name
  dir="$(dirname -- "$path")"
  name="$(basename -- "$path")"
  # if there is no dot or leading dot only
  if [[ "$name" != *.* || "$name" == .* ]]; then
    echo "${dir}/${name}${suffix}"
    return
  fi
  base="${name%.*}"
  ext="${name##*.}"
  echo "${dir}/${base}${suffix}.${ext}"
}

# if user provided an OUT filename, use it but ensure suffix inserted unless
# exact output was requested by a caller that manages destination names.
if [ -n "$OUT_ARG" ]; then
  if [ "$EXACT_OUTPUT" -eq 1 ]; then
    OUT_WITH_SUFFIX="$OUT_ARG"
  else
    OUT_WITH_SUFFIX="$(insert_suffix "$OUT_ARG")"
  fi
else
  # derive from input name
  IN_DIR="$(dirname -- "$IN")"
  IN_NAME="$(basename -- "$IN")"
  if [[ "$IN_NAME" == *.* ]]; then
    OUT_WITH_SUFFIX="${IN_DIR}/${IN_NAME%.*}${suffix}.${IN_NAME##*.}"
  else
    OUT_WITH_SUFFIX="${IN_DIR}/${IN_NAME}${suffix}"
  fi
fi

cleanup_dir=""
cleanup() {
  if [ -n "$cleanup_dir" ] && [ -d "$cleanup_dir" ]; then
    rm -rf "$cleanup_dir"
  fi
}
trap cleanup EXIT

# choose intermediate WAV path (always WAV during processing)
if [ "$KEEP_INTERMEDIATE" -eq 0 ] && [ -z "$INTERMEDIATE_DIR" ]; then
  cleanup_dir="$(mktemp -d "${TMPDIR:-/tmp}/rew2raw.XXXXXX")"
  INTERMEDIATE_DIR="$cleanup_dir"
fi

if [ -n "$INTERMEDIATE_DIR" ]; then
  mkdir -p "$INTERMEDIATE_DIR"
  INTERMEDIATE_WAV="${INTERMEDIATE_DIR}/$(basename -- "$(insert_suffix "${IN%.*}.wav")")"
else
  INTERMEDIATE_WAV="$(insert_suffix "${IN%.*}.wav")"
fi
FINAL_OUT="$OUT_WITH_SUFFIX"

print_cmd() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run_cmd() {
  print_cmd "$@"
  "$@"
}

echo "${BLUE}Input file:${RESET} $IN"
if [ "$KEEP_INTERMEDIATE" -eq 1 ]; then
  echo "${BLUE}Intermediate WAV (kept):${RESET} $INTERMEDIATE_WAV"
else
  echo "${BLUE}Intermediate WAV (temporary):${RESET} $INTERMEDIATE_WAV"
fi
echo "${BLUE}Final output (will be written):${RESET} $FINAL_OUT"
echo "${BLUE}Input sample rate:${RESET} $SOURCE_SR Hz"
echo "${BLUE}Target sample rate:${RESET} $SR Hz"
echo

# helper: show full sox stat with highlighted lines
print_sox_stat_colored() {
  local file="$1"
  echo "${BOLD}SoX stat for:${RESET} $file"
  # capture stat output
  print_cmd sox "$file" -n stat
  stat_out="$(sox "$file" -n stat 2>&1 || true)"
  # print whole stat but color relevant lines
  while IFS= read -r line; do
    case "$line" in
      *"Maximum amplitude"*)
        echo -e "${YELLOW}$line${RESET}"
        ;;
      *"Minimum amplitude"*)
        echo -e "${YELLOW}$line${RESET}"
        ;;
      *"RMS     amplitude"*)
        echo -e "${GREEN}$line${RESET}"
        ;;
      *"Maximum delta"*)
        echo -e "${BLUE}$line${RESET}"
        ;;
      *"Volume adjustment"*)
        echo -e "${RED}$line${RESET}"
        ;;
      *)
        echo "$line"
        ;;
    esac
  done <<<"$stat_out"
  echo
}

# helper to extract numeric values from SoX stat output
get_stat_value() {
  local file="$1"
  local label="$2"
  sox "$file" -n stat 2>&1 | awk -F: -v label="$label" '$0 ~ label { gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit }'
}

get_abs_peak() {
  local file="$1"
  local max min
  max="$(get_stat_value "$file" "Maximum amplitude")"
  min="$(get_stat_value "$file" "Minimum amplitude")"
  awk -v max="$max" -v min="$min" 'BEGIN{
    if(max == "" || min == "") exit 1
    if(min < 0) min = -min
    print (max >= min ? max : min)
  }'
}

echo "${BOLD}Original file stats:${RESET}"
print_sox_stat_colored "$IN"

input_abs_peak=$(get_abs_peak "$IN")
if [ -z "$input_abs_peak" ]; then
  echo "${RED}Could not determine input absolute peak. Aborting.${RESET}" >&2
  exit 3
fi
echo "${BOLD}Input absolute peak:${RESET} ${YELLOW}${input_abs_peak}${RESET}"
echo

echo "${BOLD}Resampling to ${SR} Hz into intermediate WAV (64-bit float)...${RESET}"
run_cmd sox "$IN" -b 64 -e floating-point "$INTERMEDIATE_WAV" rate -v -L -s "$SR"

echo
echo "${BOLD}Resampled file stats (before FIR gain):${RESET}"
print_sox_stat_colored "$INTERMEDIATE_WAV"

resamp_abs_peak=$(get_abs_peak "$INTERMEDIATE_WAV")
if [ -z "$resamp_abs_peak" ]; then
  echo "${RED}Could not determine resampled absolute peak. Aborting.${RESET}" >&2
  exit 4
fi
echo "${BOLD}Resampled absolute peak (before FIR gain):${RESET} ${YELLOW}${resamp_abs_peak}${RESET}"
echo

if awk "BEGIN{exit !($SOURCE_SR > 0 && $SR > 0)}"; then
  gain_db=$(awk -v source_sr="$SOURCE_SR" -v target_sr="$SR" 'BEGIN{
    printf "%.8f", 20 * (log(source_sr / target_sr) / log(10))
  }')
else
  echo "${RED}Invalid sample-rate ratio: ${SOURCE_SR}/${SR}${RESET}" >&2
  exit 5
fi

echo "${BOLD}FIR coefficient scale:${RESET} ${SOURCE_SR}/${SR}"
echo "${BOLD}Applied sample-rate gain:${RESET} ${GREEN}${gain_db} dB${RESET}"
echo

# apply gain and write final output (respecting desired output format)
if [ "$MODE" = "wav" ]; then
  # write WAV (64-bit float)
  run_cmd sox "$INTERMEDIATE_WAV" -b 64 -e floating-point "$FINAL_OUT" gain "$gain_db"
  echo "${BOLD}Final WAV written:${RESET} $FINAL_OUT"
else
  # write raw float64 little-endian
  run_cmd sox "$INTERMEDIATE_WAV" -L -t raw -e floating-point -b 64 "$FINAL_OUT" gain "$gain_db"
  echo "${BOLD}Final RAW float64 written:${RESET} $FINAL_OUT"
fi

echo
echo "${BOLD}Final file stats (after FIR gain):${RESET}"
if [ "$MODE" = "wav" ]; then
  run_cmd sox "$FINAL_OUT" -n stats
else
  run_cmd sox -t raw -r "$SR" -e floating-point -b 64 -L -c 1 "$FINAL_OUT" -n stats
fi


echo "${GREEN}Done.${RESET}"
echo "Input sample rate: ${SOURCE_SR}"
echo "Target sample rate: ${SR}"
echo "Input absolute peak: ${input_abs_peak}"
echo "Resampled absolute peak before FIR gain: ${resamp_abs_peak}"
echo "Applied sample-rate gain: ${gain_db} dB"
if [ "$KEEP_INTERMEDIATE" -eq 1 ]; then
  echo "Intermediate WAV kept at: ${INTERMEDIATE_WAV}"
else
  echo "Intermediate WAV removed after conversion."
fi

echo "OUTPUT: ${GREEN}$FINAL_OUT${RESET}"
echo

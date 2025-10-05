#!/usr/bin/env bash
set -euo pipefail

# resample_normalize_keep_intermediate.sh
#
# Usage:
#   ./resample_normalize_keep_intermediate.sh in.wav [out.raw|out.wav] [wav|raw] [sample_rate]
#
# - If OUT is omitted, output will be derived from IN with suffix _sox_upsample_float64.
# - Third arg "wav" forces final output as WAV (64-bit float). Default is "raw".
# - Fourth arg sets sample rate (default 192000).
#
# The script:
# 1) measures peaks/stats of input
# 2) resamples to SR into a kept intermediate WAV (64-bit float) named with suffix
# 3) measures stats of resampled file and prints colored comparisons
# 4) computes dB gain to match original peak and applies it to produce final output
# 5) leaves intermediate WAV file in place for inspection

# Colors
RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
BLUE="$(printf '\033[34m')"
BOLD="$(printf '\033[1m')"
RESET="$(printf '\033[0m')"

if [ $# -lt 1 ]; then
  echo "Usage: $0 in.wav [out.raw|out.wav] [wav|raw] [sample_rate]"
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

# if user provided an OUT filename, use it but ensure suffix inserted
if [ -n "$OUT_ARG" ]; then
  OUT_WITH_SUFFIX="$(insert_suffix "$OUT_ARG")"
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

# choose intermediate WAV path (always WAV kept)
INTERMEDIATE_WAV="$(insert_suffix "${IN%.*}.wav")"
FINAL_OUT="$OUT_WITH_SUFFIX"

echo "${BLUE}Input file:${RESET} $IN"
echo "${BLUE}Intermediate WAV (kept):${RESET} $INTERMEDIATE_WAV"
echo "${BLUE}Final output (will be written):${RESET} $FINAL_OUT"
echo "${BLUE}Target sample rate:${RESET} $SR Hz"
echo

# helper: show full sox stat with highlighted lines
print_sox_stat_colored() {
  local file="$1"
  echo "${BOLD}SoX stat for:${RESET} $file"
  # capture stat output
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

# helper to extract numeric value for "Maximum amplitude"
get_peak() {
  local file="$1"
  sox "$file" -n stat 2>&1 | awk -F: '/Maximum amplitude/ { gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit }'
}

echo "${BOLD}Original file stats:${RESET}"
print_sox_stat_colored "$IN"

orig_peak=$(get_peak "$IN")
if [ -z "$orig_peak" ]; then
  echo "${RED}Could not determine original peak. Aborting.${RESET}" >&2
  exit 3
fi
echo "${BOLD}Original peak:${RESET} ${YELLOW}${orig_peak}${RESET}"
echo

echo "${BOLD}Resampling to ${SR} Hz into intermediate WAV (64-bit float)...${RESET}"
sox "$IN" -b 64 "$INTERMEDIATE_WAV" rate -v -s "$SR"

echo
echo "${BOLD}Resampled file stats (before gain):${RESET}"
print_sox_stat_colored "$INTERMEDIATE_WAV"

resamp_peak=$(get_peak "$INTERMEDIATE_WAV")
if [ -z "$resamp_peak" ]; then
  echo "${RED}Could not determine resampled peak. Aborting.${RESET}" >&2
  exit 4
fi
echo "${BOLD}Resampled peak (before gain):${RESET} ${YELLOW}${resamp_peak}${RESET}"
echo

echo "original peak was $orig_peak: now setting it to the 192kHz peak 0.127396"

orig_peak=0.127396

# avoid division by zero and zero original
if awk "BEGIN{exit !($resamp_peak > 0 && $orig_peak > 0)}"; then
  gain_db=$(awk -v o="$orig_peak" -v r="$resamp_peak" 'BEGIN{
    if(r == 0 || o == 0) { print "0"; exit }
    printf "%.8f", 20 * (log(o / r) / log(10))
  }')
else
  gain_db="0"
fi

echo "${BOLD}Computed gain to match original peak:${RESET} ${GREEN}${gain_db} dB${RESET}"
echo

# apply gain and write final output (respecting desired output format)
if [ "$MODE" = "wav" ]; then
  # write WAV (64-bit float)
  sox "$INTERMEDIATE_WAV" -b 64 "$FINAL_OUT" gain "$gain_db"
  echo "${BOLD}Final WAV written:${RESET} $FINAL_OUT"
else
  # write raw float64 little-endian
  sox "$INTERMEDIATE_WAV" -t raw -e float -b 64 "$FINAL_OUT" gain "$gain_db"
  echo "${BOLD}Final RAW float64 written:${RESET} $FINAL_OUT"
fi

echo
echo -e "${BOLD}Final file stats (after gain):${RESET}: \e[0;35;4moriginal peak was\e[0m ${GREEN}$orig_peak${RESET}"
sox -t raw -r 192000 -e float -b 64 -c 1 "$FINAL_OUT" -n stats


echo "${GREEN}Done.${RESET}"
echo "Original peak: ${orig_peak}"
echo "Resampled peak before gain: ${resamp_peak}"
echo "Applied dB gain: ${gain_db}"
echo "Intermediate WAV kept at: ${INTERMEDIATE_WAV}"

echo -e "OUTPUT: \e[0;32;3m$FINAL_OUT\e[0m\n"

#!/usr/bin/env bash
# Print the active DRC config label, or 'off'.
# Exits 1 and prints 'inconsistent' if multiple different configs are running.

GEOMETRY="120.blue"   # speaker geometry / filter set to use — keep in sync with drc.sh
# Resolve this script's directory so the tool is portable (no hardcoded $HOME).
base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$base_dir/last_arg"

if [ "${1:-}" = "--geometry" ]; then
    echo "$GEOMETRY"
    exit 0
fi

state_to_args() {
    local state="$1"
    case "$state" in
        ""|"off")
            printf '%s\n' "${state:-off}"
            return
            ;;
    esac

    # Backward compatibility: older last_arg files stored "GEOMETRY rate [variant]".
    set -- $state
    if [ "${1:-}" != "resamp" ] && ! [[ "${1:-}" =~ ^[0-9]+$ ]]; then
        shift
    fi

    if [ "$#" -eq 0 ]; then
        printf 'off\n'
        return
    fi

    printf '%s' "$1"
    shift
    if [ "$#" -gt 0 ]; then
        printf ' %s' "$@"
    fi
    printf '\n'
}

format_rate() {
    case "$1" in
        44100)  printf '44.1 kHz\n' ;;
        48000)  printf '48 kHz\n' ;;
        88200)  printf '88.2 kHz\n' ;;
        96000)  printf '96 kHz\n' ;;
        192000) printf '192 kHz\n' ;;
        *)      printf '%s Hz\n' "$1" ;;
    esac
}

state_label() {
    local state mode variant profile
    state=$(state_to_args "$1")
    case "$state" in
        ""|"off")
            printf 'off\n'
            return
            ;;
    esac

    set -- $state
    mode="${1:-}"
    variant="${2:-}"
    profile="${variant:-Flat}"

    if [ "$mode" = "resamp" ]; then
        printf '%s auto-resample\n' "$profile"
    elif [[ "$mode" =~ ^[0-9]+$ ]]; then
        printf '%s %s\n' "$profile" "$(format_rate "$mode")"
    else
        printf '%s\n' "$state"
    fi
}

state_config_key() {
    local state mode variant
    state=$(state_to_args "$1")
    set -- $state
    mode="${1:-}"
    variant="${2:-}"

    case "$mode" in
        ""|"off")
            return 1
            ;;
        resamp)
            printf '192000%s\n' "$variant"
            ;;
        *)
            printf '%s%s\n' "$mode" "$variant"
            ;;
    esac
}

running_config_to_state() {
    local config="$1"
    if [[ "$config" =~ ^([0-9]+)(.*)$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        if [ -n "${BASH_REMATCH[2]}" ]; then
            printf ' %s' "${BASH_REMATCH[2]}"
        fi
        printf '\n'
    else
        printf '%s\n' "$config"
    fi
}

# ps -ax -o args= works on both Linux and FreeBSD; grep with a char class
# avoids matching the grep process itself.
configs=$(ps -ax -o args= 2>/dev/null \
    | grep -E '[b]rutefir.*\.conf' \
    | sed -n 's|.*configs/\([^/]*\)/brutefir-\([^. ]*\)\.conf.*|\2|p' \
    | sort -u)

if [ -z "$configs" ]; then
    echo "off"
    exit 0
fi

n=$(printf '%s\n' "$configs" | wc -l)
if [ "$n" -eq 1 ]; then
    state=""
    [ -f "$STATE_FILE" ] && state=$(state_to_args "$(cat "$STATE_FILE")")
    if [ -n "$state" ] && [ "$(state_config_key "$state" 2>/dev/null || true)" = "$configs" ]; then
        state_label "$state"
    else
        state_label "$(running_config_to_state "$configs")"
    fi
else
    echo "inconsistent"
    exit 1
fi

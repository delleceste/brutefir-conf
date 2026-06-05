#!/usr/bin/env bash
# Print the active brutefir config as "<geometry> <rate>" (e.g. 120.blue 192000), or 'off'.
# Exits 1 and prints 'inconsistent' if multiple different configs are running.

GEOMETRY="120.blue"   # speaker geometry / filter set to use — keep in sync with drc.sh

if [ "${1:-}" = "--geometry" ]; then
    echo "$GEOMETRY"
    exit 0
fi

# ps -ax -o args= works on both Linux and FreeBSD; grep with a char class
# avoids matching the grep process itself.
configs=$(ps -ax -o args= 2>/dev/null \
    | grep -E '[b]rutefir.*\.conf' \
    | sed -n 's|.*configs/\([^/]*\)/brutefir-\([^. ]*\)\.conf.*|\1 \2|p' \
    | sort -u)

if [ -z "$configs" ]; then
    echo "${GEOMETRY} off"
    exit 0
fi

n=$(printf '%s\n' "$configs" | wc -l)
if [ "$n" -eq 1 ]; then
    echo "$configs"
else
    echo "inconsistent"
    exit 1
fi

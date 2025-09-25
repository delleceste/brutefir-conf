#!/bin/bash

# Usage: ./convert_fir.sh left.wav right.wav

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <left_wav> <right_wav>"
    exit 1
fi

for input in "$@"; do
    # Check file exists
    if [ ! -f "$input" ]; then
        echo "Error: File $input not found"
        exit 1
    fi

    # Check if WAV, 32-bit float
    info=$(soxi "$input" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "Error: Cannot read $input with soxi"
        exit 1
    fi

	encoding=$(soxi "$input" 2>/dev/null  | grep "Sample Encoding")
	if [[ "$encoding" != *"32-bit"* || "$encoding" != *"Floating Point"* ]]; then
	    echo "Error: $input is not 32-bit float"
	    exit 1
	fi

    # Build output file name: replace '48k' with '192k' if present
    base=$(basename "$input" .wav)
    base_out=${base//48k/192k}
    out="${base_out}_sox_upsampled_64b_float.raw"

    # Convert: upsample to 192 kHz, 64-bit float raw
    sox "$input" -r 192000 -b 64 -e float -t raw "$out"

    if [ $? -eq 0 ]; then
        echo -e "Converted $input → '\e[0;32;4m$out\e[0m'"
    else
        echo -e "\e[1;31mError converting $input\e[0m"
        exit 1
    fi
done


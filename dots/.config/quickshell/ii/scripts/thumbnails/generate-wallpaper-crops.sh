#!/usr/bin/env bash

# Generate center-cropped wallpaper cache at exact screen resolution using ImageMagick.
# Images are cropped to WxH (gravity center) and stored in ~/.cache/wallpapers/WxH/<md5hash>.png
# The hash is computed from "file://<absolute_path>" — same scheme as Freedesktop thumbnails.
#
# Usage:
#   ./generate-wallpaper-crops.sh --file <path> --resolution <WxH>
#   ./generate-wallpaper-crops.sh --directory <path> --resolution <WxH> [--machine_progress] [--extensions <pattern>]

set -e

matches_pattern() {
    local filename="$1"
    local patterns_str="$2"
    local IFS='|'
    read -ra pattern_array <<< "$patterns_str"
    for p in "${pattern_array[@]}"; do
        if [[ "$filename" == $p ]]; then
            return 0
        fi
    done
    return 1
}

usage() {
    echo "Usage: $0 --file <path> | --directory <path> --resolution <WxH> [--machine_progress] [--extensions <pattern>]"
    exit 1
}

md5() {
    echo -n "$1" | md5sum | awk '{print $1}'
}

urlencode() {
    local str="$1"
    local encoded=""
    local c
    for ((i=0; i<${#str}; i++)); do
        c="${str:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]|/|'('|')'|'*') encoded+="$c" ;;
            *) printf -v hex '%%%02X' "'${c}'"; encoded+="$hex" ;;
        esac
    done
    echo "$encoded"
}

generate_crop() {
    local src="$1"
    local signal_dir="$2"
    local abs_path
    abs_path="$(realpath "$src")"

    if ! matches_pattern "${abs_path,,}" "$ALLOWED_EXTENSIONS"; then
        return
    fi

    local encoded_path
    encoded_path="$(urlencode "$abs_path")"
    local uri="file://$encoded_path"
    local hash
    hash="$(md5 "$uri")"
    local out="$CACHE_DIR/$hash.png"
    mkdir -p "$CACHE_DIR"

    if [ -f "$out" ]; then
        # Already cached — signal completion and skip
        if [ -n "$signal_dir" ]; then
            echo "$abs_path" > "$signal_dir/$$.done"
        fi
        return
    fi

    # Center-crop to exact resolution: scale up to cover WxH, then crop centered
    magick "$abs_path" \
        -gravity Center \
        -resize "${RESOLUTION}^" \
        -extent "${RESOLUTION}" \
        +repage \
        "$out"

    if [ -n "$signal_dir" ]; then
        echo "$abs_path" > "$signal_dir/$$.done"
    fi
}

# Parse arguments
MODE=""
TARGET=""
RESOLUTION=""
ALLOWED_EXTENSIONS="*.jpg|*.jpeg|*.png|*.webp|*.avif|*.bmp"
MACHINE_PROGRESS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file|-f)
            MODE="file"
            TARGET="$2"
            shift 2
            ;;
        --directory|-d)
            MODE="dir"
            TARGET="$2"
            shift 2
            ;;
        --resolution|-r)
            RESOLUTION="$2"
            shift 2
            ;;
        --extensions|-e)
            ALLOWED_EXTENSIONS="$2"
            shift 2
            ;;
        --machine_progress)
            MACHINE_PROGRESS=1
            shift 1
            ;;
        *)
            usage
            ;;
    esac
done

if [ -z "$MODE" ] || [ -z "$TARGET" ] || [ -z "$RESOLUTION" ]; then
    usage
fi

CACHE_DIR="$HOME/.cache/wallpapers/$RESOLUTION"

case "$MODE" in
    file)
        if [ ! -f "$TARGET" ]; then
            echo "File not found: $TARGET"
            exit 2
        fi
        generate_crop "$TARGET"
        ;;
    dir)
        if [ ! -d "$TARGET" ]; then
            echo "Directory not found: $TARGET"
            exit 2
        fi

        signal_dir=$(mktemp -d -t wallpaper_crop_signals_XXXXXX)
        trap "rm -rf '$signal_dir'" EXIT

        NUM_CPUS=$(nproc)
        MAX_JOBS=$(( NUM_CPUS / 2 ))
        (( MAX_JOBS == 0 )) && MAX_JOBS=1

        total_files=0
        for f_count in "$TARGET"/*; do
            [ -f "$f_count" ] || continue
            matches_pattern "${f_count,,}" "$ALLOWED_EXTENSIONS" && total_files=$(( total_files + 1 ))
        done

        completed_files=0
        active_jobs_count=0

        process_signals() {
            local count=0
            for signal_file in "$signal_dir"/*.done; do
                [ -f "$signal_file" ] || continue
                local finished_filepath
                finished_filepath=$(cat "$signal_file")
                completed_files=$(( completed_files + 1 ))
                if (( MACHINE_PROGRESS )); then
                    echo "PROGRESS $completed_files/$total_files FILE $finished_filepath"
                fi
                rm "$signal_file"
                count=$(( count + 1 ))
            done
            active_jobs_count=$(( active_jobs_count - count ))
        }

        for f in "$TARGET"/*; do
            [ -f "$f" ] || continue
            matches_pattern "${f,,}" "$ALLOWED_EXTENSIONS" || continue

            if (( active_jobs_count >= MAX_JOBS )); then
                wait -n
                process_signals
            fi

            generate_crop "$f" "$signal_dir" &
            active_jobs_count=$(( active_jobs_count + 1 ))
        done

        while (( active_jobs_count > 0 )); do
            wait -n
            process_signals
        done
        process_signals
        ;;
    *)
        usage
        ;;
esac

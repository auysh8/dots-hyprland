#!/bin/bash

# --- CONFIGURATION ---
DIR="$HOME/Pictures/Wallpapers/"
THEME_SCRIPT="/home/auysh/.config/quickshell/ii/scripts/colors/switchwall.sh"
INTERVAL=120

while true; do
    # 1. Pick Random Image (jpg, png, webp)
    RANDOM_IMG=$(find "$DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | shuf -n 1)

    if [ -n "$RANDOM_IMG" ] && [ -x "$THEME_SCRIPT" ]; then
        # Step A: Apply Wallpaper & Theme
        "$THEME_SCRIPT" --image "$RANDOM_IMG" --mode "dark" > /dev/null 2>&1
    fi
    
    sleep $INTERVAL
done
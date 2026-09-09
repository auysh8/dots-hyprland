#!/bin/bash
DIR="$HOME/Pictures/Wallpapers/"
THEME_SCRIPT="/home/auysh/.config/quickshell/ii/scripts/colors/switchwall.sh"
POLL_INTERVAL=1
LOCK_FILE="/tmp/quickshell-locked"

pick_random_wallpaper() {
    local wallpapers=()
    mapfile -d '' wallpapers < <(find "$DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) -print0)
    if [ "${#wallpapers[@]}" -eq 0 ]; then return 1; fi
    printf '%s\n' "${wallpapers[RANDOM % ${#wallpapers[@]}]}"
}

change_wallpaper() {
    local random_img
    random_img="$(pick_random_wallpaper)" || return 0
    if [ -n "$random_img" ] && [ -x "$THEME_SCRIPT" ]; then
        "$THEME_SCRIPT" --image "$random_img" --mode "dark" --keep-slideshow > /dev/null 2>&1
    fi
}

get_lock_state() {
    if [ -f "$LOCK_FILE" ]; then
        echo "yes"
    else
        echo "no"
    fi
}

last_state="$(get_lock_state)"

while true; do
    current_state="$(get_lock_state)"
    if [ "$last_state" = "yes" ] && [ "$current_state" = "no" ]; then
        change_wallpaper
    fi
    last_state="$current_state"
    sleep "$POLL_INTERVAL"
done

#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"

load_shell_config() {
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        eval "$(jq -r '
            "CFG_AI_STYLING=" + (.background.widgets.clock.cookie.aiStyling // false | tostring) + "\n" +
            "CFG_FORCE_DARK=" + (.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode // false | tostring) + "\n" +
            "CFG_ENABLE_APPS_SHELL=" + (.appearance.wallpaperTheming.enableAppsAndShell // true | tostring) + "\n" +
            "CFG_HARMONY=" + (.appearance.wallpaperTheming.terminalGenerationProps.harmony // "" | tostring) + "\n" +
            "CFG_HARMONIZE_THRESHOLD=" + (.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold // "" | tostring) + "\n" +
            "CFG_TERM_FG_BOOST=" + (.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost // "" | tostring) + "\n" +
            "CFG_ENABLE_QT_APPS=" + (.appearance.wallpaperTheming.enableQtApps // false | tostring) + "\n" +
            "CFG_PALETTE_TYPE=" + (.appearance.palette.type // "auto" | @sh) + "\n" +
            "CFG_ACCENT_COLOR=" + (.appearance.palette.accentColor // "" | @sh) + "\n" +
            "CFG_WALLPAPER_PATH=" + (.background.wallpaperPath // "" | @sh) + "\n" +
            "CFG_THUMBNAIL_PATH=" + (.background.thumbnailPath // "" | @sh)
        ' "$SHELL_CONFIG_FILE" 2>/dev/null)"
    fi
    CFG_AI_STYLING="${CFG_AI_STYLING:-false}"
    CFG_FORCE_DARK="${CFG_FORCE_DARK:-false}"
    CFG_ENABLE_APPS_SHELL="${CFG_ENABLE_APPS_SHELL:-true}"
    CFG_ENABLE_QT_APPS="${CFG_ENABLE_QT_APPS:-false}"
    CFG_PALETTE_TYPE="${CFG_PALETTE_TYPE:-auto}"
    CFG_ACCENT_COLOR="${CFG_ACCENT_COLOR:-}"
    CFG_WALLPAPER_PATH="${CFG_WALLPAPER_PATH:-}"
    CFG_THUMBNAIL_PATH="${CFG_THUMBNAIL_PATH:-}"
}

get_monitor_resolutions() {
    local monitor_json
    monitor_json="$(hyprctl monitors -j 2>/dev/null)"
    if [ -n "$monitor_json" ]; then
        eval "$(echo "$monitor_json" | jq -r '
            "MONITOR_MAX_W=" + ([.[].width] | max | tostring) + "\n" +
            "MONITOR_MAX_H=" + ([.[].height] | max | tostring) + "\n" +
            "MONITOR_MIN_W=" + ([.[].width] | min | tostring) + "\n" +
            "MONITOR_MIN_H=" + ([.[].height] | min | tostring) + "\n" +
            "MONITOR_NAMES=" + ([.[].name] | join(" ") | @sh)
        ' 2>/dev/null)"
    fi
    MONITOR_MAX_W="${MONITOR_MAX_W:-1920}"
    MONITOR_MAX_H="${MONITOR_MAX_H:-1080}"
    MONITOR_MIN_W="${MONITOR_MIN_W:-1920}"
    MONITOR_MIN_H="${MONITOR_MIN_H:-1080}"
    MONITOR_NAMES="${MONITOR_NAMES:-}"
}

handle_kde_material_you_colors() {
    # Check if Qt app theming is enabled in config
    if [ "$CFG_ENABLE_QT_APPS" == "false" ]; then
        return
    fi

    # Map $type_flag to allowed scheme variants for kde-material-you-colors-wrapper.sh
    local kde_scheme_variant=""
    case "$type_flag" in
        scheme-content|scheme-expressive|scheme-fidelity|scheme-fruit-salad|scheme-monochrome|scheme-neutral|scheme-rainbow|scheme-tonal-spot)
            kde_scheme_variant="$type_flag"
            ;;
        *)
            kde_scheme_variant="scheme-tonal-spot" # default
            ;;
    esac
    "$XDG_CONFIG_HOME"/matugen/templates/kde/kde-material-you-colors-wrapper.sh --scheme-variant "$kde_scheme_variant"
}

pre_process() {
    local mode_flag="$1"
    # Set GNOME color-scheme asynchronously to avoid blocking color generation
    if [[ "$mode_flag" == "dark" ]]; then
        (
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
            gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
        ) &
    elif [[ "$mode_flag" == "light" ]]; then
        (
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
            gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
        ) &
    fi

    if [ ! -d "$CACHE_DIR"/user/generated ]; then
        mkdir -p "$CACHE_DIR"/user/generated
    fi
}

post_process() {
    local screen_width="$1"
    local screen_height="$2"
    local wallpaper_path="$3"

    handle_kde_material_you_colors &
    "$SCRIPT_DIR/code/material-code-set-color.sh" &
}

check_and_prompt_upscale() {
    local img="$1"
    local min_width_desired="${MONITOR_MAX_W:-1920}"
    local min_height_desired="${MONITOR_MAX_H:-1080}"

    if command -v identify &>/dev/null && [ -f "$img" ]; then
        local img_width img_height
        if is_video "$img"; then # Not check resolution for videos, just let em pass
            img_width=$min_width_desired
            img_height=$min_height_desired
        else
            img_width=$(identify -format "%w" "$img" 2>/dev/null)
            img_height=$(identify -format "%h" "$img" 2>/dev/null)
        fi
        if [[ "$img_width" -lt "$min_width_desired" || "$img_height" -lt "$min_height_desired" ]]; then
            action=$(notify-send "Upscale?" \
                "Image resolution (${img_width}x${img_height}) is lower than screen resolution (${min_width_desired}x${min_height_desired})" \
                -A "open_upscayl=Open Upscayl"\
                -a "Wallpaper switcher")
            if [[ "$action" == "open_upscayl" ]]; then
                if command -v upscayl &>/dev/null; then
                    nohup upscayl > /dev/null 2>&1 &
                else
                    action2=$(notify-send \
                        -a "Wallpaper switcher" \
                        -c "im.error" \
                        -A "install_upscayl=Install Upscayl (Arch)" \
                        "Install Upscayl?" \
                        "yay -S upscayl-bin")
                    if [[ "$action2" == "install_upscayl" ]]; then
                        kitty -1 yay -S upscayl-bin
                        if command -v upscayl &>/dev/null; then
                            nohup upscayl > /dev/null 2>&1 &
                        fi
                    fi
                fi
            fi
        fi
    fi
}

CUSTOM_DIR="$XDG_CONFIG_HOME/hypr/custom"
RESTORE_SCRIPT_DIR="$CUSTOM_DIR/scripts"
RESTORE_SCRIPT="$RESTORE_SCRIPT_DIR/__restore_video_wallpaper.sh"
THUMBNAIL_DIR="$RESTORE_SCRIPT_DIR/mpvpaper_thumbnails"
VIDEO_OPTS="no-audio loop hwdec=auto scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-scale-x=1.0 video-scale-y=1.0 video-align-x=0.5 video-align-y=0.5 load-scripts=no"

is_video() {
    local extension="${1##*.}"
    [[ "$extension" == "mp4" || "$extension" == "webm" || "$extension" == "mkv" || "$extension" == "avi" || "$extension" == "mov" ]] && return 0 || return 1
}

kill_existing_mpvpaper() {
    pkill -f -9 mpvpaper || true
}

create_restore_script() {
    local video_path=$1
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# Generated by switchwall.sh - Don't modify it by yourself.
# Time: $(date)

pkill -f -9 mpvpaper

for monitor in \$(hyprctl monitors -j | jq -r '.[] | .name'); do
    mpvpaper -o "$VIDEO_OPTS" "\$monitor" "$video_path" &
    sleep 0.1
done
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"
}

remove_restore() {
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# The content of this script will be generated by switchwall.sh - Don't modify it by yourself.
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
}

set_wallpaper_path() {
    local path="$1"
    local stop_slideshow="${2:-}"
    local filter='.background.wallpaperPath = $path'
    if [[ -n "$stop_slideshow" ]]; then
        filter+=' | (if ((.background.slideshow.enable)? // false) == true then .background.slideshow.enable = false else . end)'
    fi
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        jq --arg path "$path" "$filter" "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        CFG_WALLPAPER_PATH="$path"
    fi
}

set_thumbnail_path() {
    local path="$1"
    if [ -f "$SHELL_CONFIG_FILE" ] && [ "$CFG_THUMBNAIL_PATH" != "$path" ]; then
        jq --arg path "$path" '.background.thumbnailPath = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        CFG_THUMBNAIL_PATH="$path"
    fi
}

get_type_from_config() {
    echo "${CFG_PALETTE_TYPE:-auto}"
}
set_type() {
    local type="$1"
    if [ -f "$SHELL_CONFIG_FILE" ] && [ "$CFG_PALETTE_TYPE" != "$type" ]; then
        jq --arg type "$type" '.appearance.palette.type = $type' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        CFG_PALETTE_TYPE="$type"
    fi
}
get_accent_color_from_config() {
    echo "${CFG_ACCENT_COLOR:-}"
}
set_accent_color() {
    local color="$1"
    if [ -f "$SHELL_CONFIG_FILE" ] && [ "$CFG_ACCENT_COLOR" != "$color" ]; then
        jq --arg color "$color" '.appearance.palette.accentColor = $color' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        CFG_ACCENT_COLOR="$color"
    fi
}

detect_scheme_type_from_image() {
    local img="$1"
    if [ -x "$SCRIPT_DIR/material-color-helper" ]; then
        "$SCRIPT_DIR/material-color-helper" scheme "$img" 2>/dev/null | tr -d '\n'
    else
        source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate" 2>/dev/null
        python3 "$SCRIPT_DIR/scheme_for_image.py" "$img" 2>/dev/null | tr -d '\n'
        deactivate 2>/dev/null
    fi
}

switch() {
    local lockfile="/tmp/wallpaper_switch.lock"
    
    # Prevent concurrent switches
    if ! mkdir "$lockfile" 2>/dev/null; then
        echo "Wallpaper switch already in progress, ignoring..."
        return 0
    fi
    trap "rmdir '$lockfile' 2>/dev/null" EXIT

    imgpath="$1"
    mode_flag="$2"
    type_flag="$3"
    color_flag="$4"
    color="$5"

    if [[ -z "$imgpath" && "$color_flag" != "1" ]]; then
        echo 'Aborted'
        exit 0
    fi

    # Single-pass monitor resolution detection
    get_monitor_resolutions

    # Start Gemini auto-categorization if enabled
    if [[ "$CFG_AI_STYLING" == "true" ]]; then
        categorize_wallpaper "$imgpath" &
    fi

    # Handle wallpaper switching immediately in main thread
    if [[ "$color_flag" != "1" ]]; then

        check_and_prompt_upscale "$imgpath" &
        kill_existing_mpvpaper

        if is_video "$imgpath"; then
            mkdir -p "$THUMBNAIL_DIR"
            # Set wallpaper path
            set_wallpaper_path "$imgpath" "${stop_slideshow:-}"
            # Start mpvpaper
            local video_path="$imgpath"
            monitors="${MONITOR_NAMES:-$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | .name')}"
            for monitor in $monitors; do
                mpvpaper -o "$VIDEO_OPTS" "$monitor" "$video_path" &
                sleep 0.1
            done
            create_restore_script "$video_path"
        else
            # Ensure pre-crop cache is freshly generated if needed
            if [ -n "$imgpath" ] && [ -f "$imgpath" ]; then
                "$SCRIPT_DIR/../thumbnails/generate-wallpaper-crops.sh" --file "$imgpath" --resolution "${MONITOR_MAX_W}x${MONITOR_MAX_H}"
            fi

            # Update wallpaper path in config
            set_wallpaper_path "$imgpath" "${stop_slideshow:-}"
            remove_restore
        fi
    fi

    # The picture is on screen and config is updated; the
    # rest of this function is the palette, which a slideshow leaves alone.
    if [[ -n "${picture_only_flag:-}" ]]; then
        return 0
    fi

    # Kill any previous color generation jobs
    pkill -f "generate_colors_material.py" 2>/dev/null
    pkill -f "matugen" 2>/dev/null
    pkill -f "gemini-categorize-wallpaper.sh" 2>/dev/null

    # Background the heavy tasks: Gemini, Thumbnail, Color Gen
    (
        # Set up args for background tasks
        local matugen_args=()
        local generate_colors_material_args=()

        if [[ "$color_flag" == "1" ]]; then
            matugen_args=(color hex "$color")
            generate_colors_material_args=(--color "$color")
        else
            # ⭐ THE KEY FIX: Create a small thumbnail for color extraction ⭐
            local color_thumb="$CACHE_DIR/color_extraction_thumb.jpg"
            
            if is_video "$imgpath"; then
                # For videos: Extract frame and resize to 800x600
                thumbnail="$THUMBNAIL_DIR/$(basename "$imgpath").jpg"
                nice -n 10 ionice -c3 ffmpeg -y \
                    -i "$imgpath" \
                    -vf "scale=800:-1:flags=fast_bilinear" \
                    -vframes 1 \
                    -q:v 5 \
                    "$color_thumb" 2>/dev/null
                # Also create display thumbnail
                cp "$color_thumb" "$thumbnail"
                set_thumbnail_path "$thumbnail"
            else
                # For static images: Resize to 256x256 BEFORE color extraction
                # This reduces processing time significantly and saves CPU/heat.
                if [ -x "$SCRIPT_DIR/material-color-helper" ]; then
                    nice -n 19 ionice -c3 "$SCRIPT_DIR/material-color-helper" thumbnail "$imgpath" "$color_thumb" 256 85 2>/dev/null
                else
                    nice -n 19 ionice -c3 convert "$imgpath" \
                        -resize 256x256\> \
                        -quality 85 \
                        "$color_thumb" 2>/dev/null
                fi
            fi
            
            # ⭐ Use the SMALL thumbnail for color extraction (not the full 8K image!)
            matugen_args=(image "$color_thumb" --source-color-index 0)
            generate_colors_material_args=(--path "$color_thumb")
        fi

        # 2. MEDIUM PRIORITY: AI categorize in background (lowest priority)
        if [[ "$CFG_AI_STYLING" == "true" ]]; then
            (
                nice -n 19 ionice -c3 "$SCRIPT_DIR/../ai/gemini-categorize-wallpaper.sh" "$imgpath" \
                > "$STATE_DIR/user/generated/wallpaper/category.txt"
            ) &
        fi

        # Determine mode if not set
        if [[ -z "$mode_flag" ]]; then
            current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'") || current_mode="dark"
            [[ "$current_mode" =~ "dark" ]] && mode_flag="dark" || mode_flag="light"
        fi

        # Auto-detect scheme if needed
        if [[ "$type_flag" == "auto" || -z "$type_flag" ]]; then
            allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot)
            if [[ -n "$imgpath" && -f "$imgpath" ]]; then
                detected_type="$(detect_scheme_type_from_image "$imgpath")"
                valid_detected=0
                for t in "${allowed_types[@]}"; do
                    if [[ "$detected_type" == "$t" ]]; then
                        valid_detected=1
                        break
                    fi
                done
                if [[ $valid_detected -eq 1 ]]; then
                    type_flag="$detected_type"
                else
                    type_flag="scheme-tonal-spot"
                fi
            else
                type_flag="scheme-tonal-spot"
            fi
        fi

        # Enforce mode for terminal
        if [[ -n "$mode_flag" ]]; then
            matugen_args+=(--mode "$mode_flag")
            if [[ "$CFG_FORCE_DARK" == "true" ]]; then
                generate_colors_material_args+=(--mode "dark")
            else
                generate_colors_material_args+=(--mode "$mode_flag")
            fi
        fi
        [[ -n "$type_flag" ]] && matugen_args+=(--type "$type_flag") && generate_colors_material_args+=(--scheme "$type_flag")
        generate_colors_material_args+=(--termscheme "$terminalscheme" --blend_bg_fg)
        generate_colors_material_args+=(--cache "$STATE_DIR/user/generated/color.txt")

        pre_process "$mode_flag"

        # Check if app and shell theming is enabled
        if [[ "$CFG_ENABLE_APPS_SHELL" == "false" ]]; then
            exit 0
        fi

        # Harmony settings
        [[ "$CFG_HARMONY" != "null" && -n "$CFG_HARMONY" ]] && generate_colors_material_args+=(--harmony "$CFG_HARMONY")
        [[ "$CFG_HARMONIZE_THRESHOLD" != "null" && -n "$CFG_HARMONIZE_THRESHOLD" ]] && generate_colors_material_args+=(--harmonize_threshold "$CFG_HARMONIZE_THRESHOLD")
        [[ "$CFG_TERM_FG_BOOST" != "null" && -n "$CFG_TERM_FG_BOOST" ]] && generate_colors_material_args+=(--term_fg_boost "$CFG_TERM_FG_BOOST")

        # 3. HIGH PRIORITY: Generate colors (needed for UI)
        nice -n 5 ionice -c2 -n4 matugen "${matugen_args[@]}" &>/dev/null
        source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"
        nice -n 5 ionice -c2 -n4 python3 "$SCRIPT_DIR/generate_colors_material.py" \
            "${generate_colors_material_args[@]}" > "$STATE_DIR"/user/generated/material_colors.scss
        
        # 4. APPLY colors (Immediate)
        "$SCRIPT_DIR"/applycolor.sh
        deactivate

        # 5. FINAL: Post processing
        post_process "$MONITOR_MIN_W" "$MONITOR_MIN_H" "$imgpath"
    ) &
}

main() {
    imgpath=""
    mode_flag=""
    type_flag=""
    color_flag=""
    color=""
    noswitch_flag=""
    picture_only_flag=""
    keep_slideshow_flag=""
    stop_slideshow=""

    load_shell_config

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                mode_flag="$2"
                shift 2
                ;;
            --type)
                type_flag="$2"
                set_type "$2"
                shift 2
                ;;
            --color)
                if [[ "$2" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
                    set_accent_color "$2"
                    shift 2
                elif [[ "$2" == "clear" ]]; then
                    set_accent_color ""
                    shift 2
                else
                    set_accent_color $(hyprpicker --no-fancy)
                    shift
                fi
                ;;
            --image)
                imgpath="$2"
                shift 2
                ;;
            --noswitch)
                noswitch_flag="1"
                imgpath="${CFG_WALLPAPER_PATH:-}"
                shift
                ;;
            --picture-only)
                picture_only_flag="1"
                shift
                ;;
            --keep-slideshow)
                keep_slideshow_flag="1"
                shift
                ;;
            *)
                if [[ -z "$imgpath" ]]; then
                    imgpath="$1"
                fi
                shift
                ;;
        esac
    done

    # A picked accent normally routes switch() down the colour branch, which
    # never reaches the code that records the wallpaper. Nothing here is going
    # to generate colours anyway, so drop it and take the image branch — which
    # also leaves the accent itself untouched, since only the colour path
    # clears it.
    if [[ -n "$picture_only_flag" ]]; then
        color_flag=""
        color=""
    fi

    # If accentColor is set in config, use it
    config_color="$(get_accent_color_from_config)"
    if [[ "$config_color" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
        color_flag="1"
        color="$config_color"
    fi

    # If type_flag is not set, get it from config
    if [[ -z "$type_flag" ]]; then
        type_flag="$(get_type_from_config)"
    fi

    # Validate type_flag (allow 'auto' as well)
    allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot auto)
    valid_type=0
    for t in "${allowed_types[@]}"; do
        if [[ "$type_flag" == "$t" ]]; then
            valid_type=1
            break
        fi
    done
    if [[ $valid_type -eq 0 ]]; then
        echo "[switchwall.sh] Warning: Invalid type '$type_flag', defaulting to 'auto'" >&2
        type_flag="auto"
    fi

    # Only prompt for wallpaper if not using --color and not using --noswitch and no imgpath set
    if [[ -z "$imgpath" && -z "$color_flag" && -z "$noswitch_flag" && -z "$picture_only_flag" ]]; then
        cd "$(xdg-user-dir PICTURES)/Wallpapers/showcase" 2>/dev/null || cd "$(xdg-user-dir PICTURES)/Wallpapers" 2>/dev/null || cd "$(xdg-user-dir PICTURES)" || return 1
        imgpath="$(kdialog --getopenfilename . --title 'Choose wallpaper')"
    fi

    # If type_flag is 'auto', we will detect it inside switch (in background) to avoid blocking
    if [[ "$type_flag" == "auto" && -z "$imgpath" ]]; then
         # Only warn if we don't have an image path by now
         echo "[switchwall] Warning: No image to auto-detect scheme from (delayed)" >&2
    fi

    # A picture chosen on purpose is the end of a rotation. Kept apart from the
    # accent rule above so the rotation's own ticks, which do want the accent
    # cleared when they regenerate the palette, are not caught by it.
    if [[ -n "$imgpath" && -z "$noswitch_flag" && -z "$picture_only_flag" && -z "$keep_slideshow_flag" ]]; then
        stop_slideshow=1
    fi

    # If mode_flag is dark or light, try to find a variant with that mode suffix
    if [[ "$mode_flag" == "dark" || "$mode_flag" == "light" ]]; then
        # Get directory, filename without extension, and extension
        local imgdir="$(dirname "$imgpath")"
        local imgbase="$(basename "$imgpath")"
        local imgname="${imgbase%.*}"
        local imgext="${imgbase##*.}"

        # Strip existing -dark or -light suffix
        local stripped_name="${imgname%-dark}"
        stripped_name="${stripped_name%-light}"

        # Construct the new path with the requested mode suffix
        local new_imgpath="${imgdir}/${stripped_name}-${mode_flag}.${imgext}"
        local new_stripped_imgpath="${imgdir}/${stripped_name}.${imgext}"

        # If the variant exists, use it
        if [[ -f "$new_imgpath" ]]; then
            imgpath="$new_imgpath"
        elif [[ -f "$new_stripped_imgpath" ]]; then
            imgpath="$new_stripped_imgpath"
        fi
    fi

    switch "$imgpath" "$mode_flag" "$type_flag" "$color_flag" "$color"
}

main "$@"

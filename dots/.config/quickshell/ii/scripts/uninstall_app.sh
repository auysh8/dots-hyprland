#!/bin/bash
# Usage: ./uninstall_app.sh <desktop_file_path> [app_id] [app_name]

DESKTOP_FILE="$1"
APP_ID="$2"
APP_NAME="$3"

echo "------------------------------------------------"
echo " Uninstall Helper"
echo "------------------------------------------------"
echo "Target ID: $APP_ID"
echo "Target Name: $APP_NAME"

# If DESKTOP_FILE is undefined or empty, try to find it
if [ -z "$DESKTOP_FILE" ] || [ "$DESKTOP_FILE" == "undefined" ]; then
    echo "⚠️  Desktop file path not provided. Searching..."
    
    # Common locations
    LOCATIONS=(
        "/usr/share/applications"
        "$HOME/.local/share/applications"
        "/var/lib/flatpak/exports/share/applications"
        "$HOME/.local/share/flatpak/exports/share/applications"
    )
    
    # Patterns ordered by specificity:
    # 1. Suffix match (exact ID match)
    # 2. Name based match (replace spaces with *)
    # 3. Broad fuzzy match
    
    PATTERNS=("*${APP_ID}.desktop")
    
    if [ -n "$APP_NAME" ]; then
        # Replace spaces with wildcards for name matching
        NAME_PATTERN="*${APP_NAME// /*}*.desktop"
        PATTERNS+=("$NAME_PATTERN")
    fi
    
    PATTERNS+=("*${APP_ID}*.desktop")
    
    for PATTERN in "${PATTERNS[@]}"; do
         for LOC in "${LOCATIONS[@]}"; do
            FOUND=$(find "$LOC" -maxdepth 1 -iname "$PATTERN" -print -quit 2>/dev/null)
            if [ -n "$FOUND" ]; then
                DESKTOP_FILE="$FOUND"
                echo "✅ Found (heuristic '$PATTERN'): $DESKTOP_FILE"
                break 2
            fi
        done
     done

    if [ -z "$DESKTOP_FILE" ] || [ "$DESKTOP_FILE" == "undefined" ]; then
        echo "❌ Could not find desktop file for ID: $APP_ID or Name: $APP_NAME"
    fi
fi

echo "File: $DESKTOP_FILE"

# 1. Try Pacman (System & AUR)
if [ -f "$DESKTOP_FILE" ]; then
    PKG=$(pacman -Qoq "$DESKTOP_FILE" 2>/dev/null)
    if [ -n "$PKG" ]; then
        echo "-> Identified as Pacman/AUR package: $PKG"
        read -p "⚠️  Are you sure you want to uninstall '$PKG'? (y/N): " CONFIRM
        if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
            echo "❌ Cancelled." 
        else
            echo "Running: pkexec pacman -Rns $PKG"
            pkexec pacman -Rns "$PKG"
            echo "Finished."
        fi
        read -p "Press Enter to close..."
        exit 0
    fi
fi

# 2. Try Flatpak
if [[ "$DESKTOP_FILE" == *"/flatpak/"* ]]; then
    echo "-> Identified as Flatpak based on path."
    BASENAME=$(basename "$DESKTOP_FILE" .desktop)
    read -p "⚠️  Do you want to uninstall Flatpak '$BASENAME'? (y/N): " CONFIRM
    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
        flatpak uninstall "$BASENAME"
    fi
    read -p "Press Enter to close..."
    exit 0
fi

if [ -n "$APP_ID" ]; then
    if flatpak info "$APP_ID" &>/dev/null; then
        echo "-> Identified as Flatpak by ID: $APP_ID"
        read -p "⚠️  Do you want to uninstall Flatpak '$APP_ID'? (y/N): " CONFIRM
        if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
           flatpak uninstall "$APP_ID"
        fi
        read -p "Press Enter to close..."
        exit 0
    fi
fi

# 3. Orphan / Local File Cleanup
if [[ "$DESKTOP_FILE" == *"$HOME/.local/share/applications/"* ]] && [ -f "$DESKTOP_FILE" ]; then
    echo "-> This is a local desktop file and no package owner was found."
    echo "It is likely a leftover shortcut or manually installed app."
    read -p "⚠️  Do you want to DELETE this file? (y/N): " CONFIRM
    if [[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]]; then
        rm "$DESKTOP_FILE"
        echo "✅ File deleted."
    else
        echo "Cancelled."
    fi
    read -p "Press Enter to close..."
    exit 0
fi

echo "❌ Could not determine how to uninstall this application."
read -p "Press Enter to close..."

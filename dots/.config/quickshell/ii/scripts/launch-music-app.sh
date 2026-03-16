#!/usr/bin/env bash
# QuickShell Music App Launcher
# Launches the music app as a standalone application window

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUSIC_APP="${SCRIPT_DIR}/music.qml"

# Check if music app is already running
if pgrep -f "quickshell.*music.qml" > /dev/null 2>&1; then
    # If running, toggle via IPC if possible, otherwise just bring to front
    quickshell ipc -c ii call music toggle 2>/dev/null
    exit 0
fi

# Launch as standalone app
exec quickshell --path "$MUSIC_APP"

#!/bin/bash

SCRIPT_DIR="$HOME/.config/quickshell/scripts"

# Kill existing instances to prevent duplicates
pkill -f "check_updates.sh"
pkill -f "watch_downloads"

# Start scripts in background
bash "$SCRIPT_DIR/check_updates.sh" &

if [ -x "$SCRIPT_DIR/watch_downloads" ]; then
    "$SCRIPT_DIR/watch_downloads" &
else
    python3 "$SCRIPT_DIR/watch_downloads.py" &
fi

echo "Island Automation Scripts Started."

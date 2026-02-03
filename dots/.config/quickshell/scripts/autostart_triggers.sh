#!/bin/bash

SCRIPT_DIR="$HOME/.config/quickshell/scripts"

# Kill existing instances to prevent duplicates
pkill -f "check_updates.sh"
pkill -f "watch_downloads.py"

# Start scripts in background
bash "$SCRIPT_DIR/check_updates.sh" &
python3 "$SCRIPT_DIR/watch_downloads.py" &

echo "Island Automation Scripts Started."

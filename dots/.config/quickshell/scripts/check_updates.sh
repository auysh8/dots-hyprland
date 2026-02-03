#!/bin/bash

# Log file
LOG_FILE="/tmp/qs_popup.log"

# Function to check updates
check_updates() {
    if command -v checkupdates &> /dev/null; then
        count=$(checkupdates | wc -l)
        if [ "$count" -gt 0 ]; then
             echo "neutral|System Update|$count updates available" >> "$LOG_FILE"
        fi
    elif command -v apt &> /dev/null; then
         # Allow non-interactive update check
         count=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | wc -l)
         if [ "$count" -gt 0 ]; then
             echo "neutral|System Update|$count updates available" >> "$LOG_FILE"
         fi
    fi
}

echo "Starting Update Checker..."
while true; do
    check_updates
    # Check every 30 minutes
    sleep 1800
done

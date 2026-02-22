
#!/bin/bash

LOG_FILE="/tmp/qs_popup.log"
touch "$LOG_FILE"

# --- 1. Automatically find LED files ---
CAPS_PATH=$(find /sys/class/leds -name "*capslock*" | head -n1)/brightness
NUM_PATH=$(find /sys/class/leds -name "*numlock*" | head -n1)/brightness

# Warn if not found
if [ ! -f "$CAPS_PATH" ]; then echo "ERRO: Caps Lock LED not found in /sys/class/leds"; fi
if [ ! -f "$NUM_PATH" ]; then echo "ERRO: Num Lock LED not found in /sys/class/leds"; fi

echo "Monitorando via LED (Kernel)..."
echo "Caps Path: $CAPS_PATH"
echo "Num Path: $NUM_PATH"

# Function to read state (0 or 1)
get_led_state() {
    if [ -f "$1" ]; then
        cat "$1"
    else
        echo "0"
    fi
}

# --- 2. Initial State ---
LAST_CAPS=$(get_led_state "$CAPS_PATH")
LAST_NUM=$(get_led_state "$NUM_PATH")

# --- 3. Monitoring Loop ---
while true; do
    CUR_CAPS=$(get_led_state "$CAPS_PATH")
    CUR_NUM=$(get_led_state "$NUM_PATH")

    # Check CAPS LOCK
    if [ "$CUR_CAPS" != "$LAST_CAPS" ]; then
        if [ "$CUR_CAPS" == "1" ]; then MSG="ON"; else MSG="OFF"; fi
        # Write to log for Quickshell
        echo "toggle|CAPS⇪|$MSG|generic|caps" >> "$LOG_FILE"
        LAST_CAPS="$CUR_CAPS"
    fi

    # Check NUM LOCK
    if [ "$CUR_NUM" != "$LAST_NUM" ]; then
        if [ "$CUR_NUM" == "1" ]; then MSG="ON"; else MSG="OFF"; fi
        echo "toggle|NUM ①|$MSG|generic|num" >> "$LOG_FILE"
        LAST_NUM="$CUR_NUM"
    fi

    sleep 0.5
done


#!/bin/bash

LOG_FILE="/tmp/qs_popup.log"
touch "$LOG_FILE"

# --- 1. Find Paths ---
AC_PATH=$(find /sys/class/power_supply -name "AC*" -o -name "ADP*" | head -n1)
WIFI_IFACE=$(ls /sys/class/net | grep -E '^(wlan|wlp|wifi)' | head -n1)

# Helper to read values
get_val() {
    if [ -f "$1" ]; then cat "$1"; else echo "Unknown"; fi
}

# --- 2. Initial States ---
if [ -f "$AC_PATH/online" ]; then LAST_AC=$(cat "$AC_PATH/online"); else LAST_AC="Unknown"; fi
LAST_WIFI=$(get_val "/sys/class/net/$WIFI_IFACE/operstate")

# Initialize Bluetooth
LAST_BT_COUNT=$(bluetoothctl devices Connected 2>/dev/null | wc -l)

# Initialize Music (Empty to avoid login popup)
LAST_SONG=""

# Initialize Disk Counter
DISK_CHECK_COUNTER=0

# --- 3. Monitoring Loop ---
while true; do
    # --- CHECK 1: Power ---
    if [ -f "$AC_PATH/online" ]; then
        CUR_AC=$(cat "$AC_PATH/online")
        if [ "$CUR_AC" != "$LAST_AC" ]; then
            if [ "$CUR_AC" == "1" ]; then
                echo "good|POWER|Plugged In|battery|charging" >> "$LOG_FILE"
            else
                echo "bad|POWER|Unplugged|battery|unplugged" >> "$LOG_FILE"
            fi
            LAST_AC="$CUR_AC"
        fi
    fi

    # --- CHECK 2: Wi-Fi ---
    if [ -n "$WIFI_IFACE" ]; then
        CUR_WIFI=$(get_val "/sys/class/net/$WIFI_IFACE/operstate")
        if [ "$CUR_WIFI" != "$LAST_WIFI" ] && [ "$CUR_WIFI" != "Unknown" ]; then
            # Debounce: Wait to confirm state is stable
            sleep 3
            CONFIRM_WIFI=$(get_val "/sys/class/net/$WIFI_IFACE/operstate")
            
            if [ "$CONFIRM_WIFI" == "$CUR_WIFI" ]; then
                if [ "$CUR_WIFI" == "up" ]; then
                    # Get SSID for better context
                    WIFI_SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)
                    if [ -z "$WIFI_SSID" ]; then
                        echo "good|WIFI|Connected|wifi|connected" >> "$LOG_FILE"
                    else
                        echo "good|WIFI|Connected: $WIFI_SSID|wifi|connected" >> "$LOG_FILE"
                    fi
                elif [ "$CUR_WIFI" == "down" ]; then
                    echo "bad|WIFI|Disconnected|wifi|disconnected" >> "$LOG_FILE"
                fi
                LAST_WIFI="$CUR_WIFI"
            fi
        fi
    fi

    # --- CHECK 3: Bluetooth (FIXED) ---
    # We count devices
    CUR_BT_COUNT=$(bluetoothctl devices Connected 2>/dev/null | wc -l)
    
    if [ "$CUR_BT_COUNT" != "$LAST_BT_COUNT" ]; then
        # FIX: Wait 1 second and check again. 
        # If it was just a glitch, the count will go back to normal and we ignore it.
        sleep 1
        CUR_BT_CONFIRM=$(bluetoothctl devices Connected 2>/dev/null | wc -l)

        if [ "$CUR_BT_CONFIRM" == "$CUR_BT_COUNT" ]; then
            # The change is REAL (persisted for 1s)
            if [ "$CUR_BT_COUNT" -gt "$LAST_BT_COUNT" ]; then
                 BT_NAME=$(bluetoothctl devices Connected | head -n1 | cut -d ' ' -f 3-)
                 if [ -z "$BT_NAME" ]; then BT_NAME="Device"; fi
                 echo "good|BLUETOOTH|Connected: $BT_NAME|bluetooth|connected" >> "$LOG_FILE"
            else
                 echo "bad|BLUETOOTH|Disconnected|bluetooth|disconnected" >> "$LOG_FILE"
            fi
            LAST_BT_COUNT="$CUR_BT_COUNT"
        fi
        # If they didn't match, it was a glitch, so we do nothing.
    fi

    # --- CHECK 4: Music ---
    PLAYER_STATUS=$(playerctl status 2>/dev/null)
    
    if [ "$PLAYER_STATUS" == "Playing" ]; then
        CUR_SONG=$(playerctl metadata --format '{{ title }} - {{ artist }}' 2>/dev/null)
        CUR_SONG=$(echo "$CUR_SONG" | cut -c 1-40)

        if [ -n "$CUR_SONG" ] && [ "$CUR_SONG" != "$LAST_SONG" ]; then
            # Only show popup if this is NOT the first check
            if [ -n "$LAST_SONG" ]; then
                echo "neutral|Now Playing|$CUR_SONG|media|playing" >> "$LOG_FILE"
            fi
            LAST_SONG="$CUR_SONG"
        fi
    else
        # If music stops, reset state so hitting play later triggers a popup
        if [ "$LAST_SONG" != "stopped" ]; then
            LAST_SONG="stopped"
        fi
    fi

    sleep 1.5

    # --- CHECK 5: Disk Space ---
    ((DISK_CHECK_COUNTER++))
    if [ "$DISK_CHECK_COUNTER" -ge 40 ]; then
        DISK_USAGE=$(df / --output=pcent | tail -1 | tr -dc '0-9')
        if [ "$DISK_USAGE" -ge 90 ]; then
             echo "bad|SYSTEM|Low Disk Space ($DISK_USAGE%)|generic|low" >> "$LOG_FILE"
        fi
        DISK_CHECK_COUNTER=0
    fi
done
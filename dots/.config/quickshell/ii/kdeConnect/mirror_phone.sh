#!/bin/bash
# Phone Mirroring Helper Script for KDE Connect Drawer
# Uses scrcpy for screen mirroring via USB or WiFi

CONFIG_DIR="$HOME/.config/kdeconnect-drawer"
CONFIG_FILE="$CONFIG_DIR/mirror_ip"

# Optimized scrcpy options
# --turn-screen-off: Keep phone screen off while mirroring (saves battery)
# --no-audio: Disable audio for lower latency
# --video-bit-rate=8M: Higher bitrate for quality
# --max-fps=60: Smooth 60fps
SCRCPY_OPTS="--window-title=PhoneMirror --stay-awake --window-borderless --turn-screen-off --no-audio --video-bit-rate=8M --max-fps=60"

# Check if scrcpy is installed
if ! command -v scrcpy &> /dev/null; then
    notify-send "Phone Mirror" "scrcpy is not installed. Install with: pacman -S scrcpy" -u critical
    exit 1
fi

# Check if adb is installed
if ! command -v adb &> /dev/null; then
    notify-send "Phone Mirror" "ADB is not installed. Install with: pacman -S android-tools" -u critical
    exit 1
fi

# Start ADB server if not running
adb start-server 2>/dev/null

# Check if device is connected via USB
USB_DEVICE=$(adb devices | grep -v "List" | grep "device$" | head -1)

# Check if device is connected via USB
USB_DEVICE=$(adb devices | grep -v "List" | grep "device$" | head -1)

if [ -n "$USB_DEVICE" ]; then
    notify-send "Phone Mirror" "USB Device Detected. Enabling Wireless Mode..." -t 2000
    
    # Get IP first (before restarting ADB)
    # Matches 'src <IP>' from 'ip route' to support wlan0, rndis0, etc.
    PHONE_IP=$(adb shell ip route | grep " src " | awk '{print $9}' | head -1)
    
    if [ -n "$PHONE_IP" ]; then
        echo "Detected IP via USB: $PHONE_IP"
        mkdir -p "$CONFIG_DIR"
        echo "$PHONE_IP" > "$CONFIG_FILE"
    fi

    # Enable ADB over TCP/IP on port 5555
    # This restarts the adbd daemon on the phone, dropping the USB connection briefly
    adb tcpip 5555 || true
    
    # Wait for adbd to restart
    sleep 2
    
    # Connect wirelessly immediately if we have an IP
    if [ -n "$PHONE_IP" ]; then
        adb connect "$PHONE_IP:5555" || true
    fi
    
    notify-send "Phone Mirror" "Starting mirror..." -t 2000
    scrcpy $SCRCPY_OPTS &
    exit 0
fi

# Wireless mode - try multiple methods to find phone IP

try_connect() {
    local ip=$1
    if [ -z "$ip" ]; then
        return 1
    fi
    
    local out
    out=$(adb connect "$ip:5555" 2>&1)
    
    if echo "$out" | grep -q "connected"; then
        return 0
    else
        # If we found the IP but connection refused, return specific error code 2
        if echo "$out" | grep -q "refused"; then
            return 2
        fi
        return 1
    fi
}

# Method 1A: Detect from active KDE Connect connection (Most Reliable for WiFi)
DETECTED_IP=$(ss -tunp state established | grep kdeconnect | grep ":1716" | awk '{print $5}' | sed 's/\[::ffff://;s/\]:.*//' | head -1)

if [ -n "$DETECTED_IP" ]; then
    echo "Detected IP via KDE Connect: $DETECTED_IP"
    try_connect "$DETECTED_IP"
    res=$?
    
    if [ $res -eq 0 ]; then
        mkdir -p "$CONFIG_DIR"
        echo "$DETECTED_IP" > "$CONFIG_FILE"
        notify-send "Phone Mirror" "Connected via active session: $DETECTED_IP" -t 2000
        scrcpy $SCRCPY_OPTS &
        exit 0
    elif [ $res -eq 2 ]; then
        notify-send "Phone Mirror" "Found phone at $DETECTED_IP but ADB port is closed.\n\nPlease connect via USB cable once and click this button again to enable wireless mirroring." -u critical
        exit 1
    fi
fi

# Method 1B: Try saved IP from previous connection
if [ -f "$CONFIG_FILE" ]; then
    SAVED_IP=$(cat "$CONFIG_FILE")
    if try_connect "$SAVED_IP"; then
        notify-send "Phone Mirror" "Connected via saved IP" -t 2000
        scrcpy $SCRCPY_OPTS &
        exit 0
    fi
fi

# Method 2: Try default gateway (works when PC is on phone's hotspot)
GATEWAY_IP=$(ip route | grep default | awk '{print $3}' | head -1)
if try_connect "$GATEWAY_IP"; then
    mkdir -p "$CONFIG_DIR"
    echo "$GATEWAY_IP" > "$CONFIG_FILE"
    notify-send "Phone Mirror" "Connected via hotspot gateway" -t 2000
    scrcpy $SCRCPY_OPTS &
    exit 0
fi

# Method 3: Prompt user for IP as last resort
notify-send "Phone Mirror" "Auto-detect failed, prompting for IP..." -t 2000

if command -v zenity &> /dev/null; then
    PHONE_IP=$(zenity --entry --title="Phone Mirror Setup" --text="Enter your phone's IP address:\n(Find it in Settings → Wi-Fi → Your Network → IP Address)" --width=400)
    if [ -z "$PHONE_IP" ]; then
        notify-send "Phone Mirror" "No IP address provided" -u critical
        exit 1
    fi
    
    if try_connect "$PHONE_IP"; then
        mkdir -p "$CONFIG_DIR"
        echo "$PHONE_IP" > "$CONFIG_FILE"
        scrcpy $SCRCPY_OPTS &
        exit 0
    else
        notify-send "Phone Mirror" "Could not connect to $PHONE_IP:5555\n\nMake sure:\n1. Phone and PC are on same network\n2. Run 'adb tcpip 5555' via USB first" -u critical
        exit 1
    fi
else
    notify-send "Phone Mirror" "Could not auto-detect phone.\n\nConnect via USB first to enable wireless, or install zenity for manual IP entry." -u critical
    exit 1
fi

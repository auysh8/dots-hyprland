#!/bin/bash
# Phone Mirroring Helper Script for KDE Connect Drawer
# Uses scrcpy for screen mirroring via USB or WiFi

set -u

CONFIG_DIR="$HOME/.config/kdeconnect-drawer"
CONFIG_FILE="$CONFIG_DIR/mirror_ip"
TARGET_SERIAL=""

SCRCPY_OPTS=(
  --window-title=PhoneMirror
  --stay-awake
  --window-borderless
  --turn-screen-off
  --no-audio
  --video-bit-rate=8M
  --max-fps=60
)

notify() {
  notify-send "Phone Mirror" "$1" "${@:2}"
}

fail() {
  notify "$1" -u critical
  exit 1
}

save_ip() {
  local ip="$1"
  [ -n "$ip" ] || return 0
  mkdir -p "$CONFIG_DIR"
  printf '%s\n' "$ip" > "$CONFIG_FILE"
}

start_mirror() {
  notify "Starting mirror..." -t 1600
  if [ -n "$TARGET_SERIAL" ]; then
    scrcpy --serial="$TARGET_SERIAL" "${SCRCPY_OPTS[@]}" &
  else
    scrcpy "${SCRCPY_OPTS[@]}" &
  fi
  exit 0
}

try_connect() {
  local ip="$1"
  [ -n "$ip" ] || return 1

  local out
  out="$(adb connect "$ip:5555" 2>&1)"
  if echo "$out" | grep -qi "connected\|already connected"; then
    return 0
  fi
  if echo "$out" | grep -qi "refused"; then
    return 2
  fi
  return 1
}

if ! command -v scrcpy >/dev/null 2>&1; then
  fail "scrcpy is not installed."
fi

if ! command -v adb >/dev/null 2>&1; then
  fail "adb is not installed."
fi

adb start-server >/dev/null 2>&1 || fail "Failed to start adb server."

USB_DEVICE="$(adb devices -l | awk 'NR>1 && $2=="device" && /usb:/ {print $1; exit}')"
if [ -n "$USB_DEVICE" ]; then
  notify "USB device detected. Enabling wireless mode..." -t 2000
  TARGET_SERIAL="$USB_DEVICE"

  PHONE_IP="$(adb -s "$USB_DEVICE" shell ip route 2>/dev/null | grep " src " | awk '{print $9}' | head -1)"
  save_ip "$PHONE_IP"

  if ! adb -s "$USB_DEVICE" tcpip 5555 >/dev/null 2>&1; then
    fail "Unable to enable adb tcpip mode on the USB device."
  fi

  sleep 2
  if [ -n "$PHONE_IP" ]; then
    adb connect "$PHONE_IP:5555" >/dev/null 2>&1 || true
  fi
  start_mirror
fi

# Wireless mode: try active KDE Connect session IP first.
DETECTED_IP=""
if command -v ss >/dev/null 2>&1; then
  DETECTED_IP="$(ss -tunp state established 2>/dev/null | grep kdeconnect | grep ":1716" | awk '{print $5}' | sed 's/\[::ffff://;s/\]:.*//' | head -1)"
fi

if [ -n "$DETECTED_IP" ]; then
  try_connect "$DETECTED_IP"
  res=$?
  if [ "$res" -eq 0 ]; then
    save_ip "$DETECTED_IP"
    TARGET_SERIAL="$DETECTED_IP:5555"
    notify "Connected via active KDE Connect session: $DETECTED_IP" -t 1800
    start_mirror
  elif [ "$res" -eq 2 ]; then
    fail "Found phone at $DETECTED_IP but adb port 5555 is closed. Connect via USB once to enable wireless mirroring."
  fi
fi

if [ -f "$CONFIG_FILE" ]; then
  SAVED_IP="$(cat "$CONFIG_FILE")"
  if try_connect "$SAVED_IP"; then
    TARGET_SERIAL="$SAVED_IP:5555"
    notify "Connected via saved IP: $SAVED_IP" -t 1800
    start_mirror
  fi
fi

GATEWAY_IP="$(ip route | awk '/default/ {print $3; exit}')"
if try_connect "$GATEWAY_IP"; then
  save_ip "$GATEWAY_IP"
  TARGET_SERIAL="$GATEWAY_IP:5555"
  notify "Connected via hotspot gateway: $GATEWAY_IP" -t 1800
  start_mirror
fi

notify "Auto-detect failed. Prompting for phone IP..." -t 1800
if command -v zenity >/dev/null 2>&1; then
  PHONE_IP="$(zenity --entry --title="Phone Mirror Setup" --text="Enter your phone IP address (Settings > Wi-Fi > network details)." --width=420)"
  [ -n "$PHONE_IP" ] || fail "No IP address provided."

  try_connect "$PHONE_IP"
  case "$?" in
    0)
      save_ip "$PHONE_IP"
      TARGET_SERIAL="$PHONE_IP:5555"
      start_mirror
      ;;
    2)
      fail "Phone found at $PHONE_IP but adb port 5555 is closed. Enable wireless adb once via USB."
      ;;
    *)
      fail "Could not connect to $PHONE_IP:5555. Ensure phone and PC are on the same network."
      ;;
  esac
else
  fail "Could not auto-detect phone IP. Connect via USB once, or install zenity for manual IP prompt."
fi

#!/usr/bin/env bash

# Fast-path: Check sysfs leds directly (zero subprocesses, ~0.03ms)
for led in /sys/class/leds/*capslock*/brightness; do
    if [[ -f "$led" ]]; then
        read -r val < "$led" 2>/dev/null
        if [[ "$val" -ne 0 ]]; then
            echo "Caps Lock active"
            exit 0
        fi
    fi
done

# If sysfs leds existed and were 0, Caps Lock is definitely off
if compgen -G "/sys/class/leds/*capslock*/brightness" > /dev/null; then
    exit 0
fi

# Fallback for systems without standard sysfs LED exposure
if command -v hyprctl >/dev/null 2>&1; then
    if hyprctl devices 2>/dev/null | grep -B 6 "main: yes" | grep -q "capsLock: yes"; then
        echo "Caps Lock active"
        exit 0
    fi
fi


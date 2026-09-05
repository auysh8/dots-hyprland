#!/usr/bin/env bash

# Fast-path: Read battery status and capacity using pure bash built-ins (0 subprocesses, ~0.05ms)
for battery in /sys/class/power_supply/*BAT*; do
    if [[ -d "$battery" && -f "$battery/capacity" ]]; then
        read -r capacity < "$battery/capacity" 2>/dev/null
        read -r status < "$battery/status" 2>/dev/null
        
        prefix=""
        suffix=" remaining"
        if [[ "$status" == "Charging" ]]; then
            prefix="(+) "
            suffix=""
        fi
        
        echo "${prefix}${capacity}%${suffix}"
        exit 0
    fi
done

echo ""
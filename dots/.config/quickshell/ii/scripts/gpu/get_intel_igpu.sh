#!/usr/bin/env bash
set -euo pipefail
LC_NUMERIC=C

# Intel iGPU (Iris Xe, UHD Graphics) monitoring

CARD_PATH=""
CARD_DIR=""

# Check for manual card override via INTEL_GPU_CARD env var
if [[ -n "${INTEL_GPU_CARD:-}" ]]; then
  if [[ -d "/sys/class/drm/${INTEL_GPU_CARD}/device" ]]; then
    CARD_PATH="/sys/class/drm/${INTEL_GPU_CARD}/device"
    CARD_DIR="/sys/class/drm/${INTEL_GPU_CARD}"
  else
    echo '{}'
    exit 0
  fi
else
  for c in /sys/class/drm/card*; do
    d="$c/device"
    [[ -r "$d/vendor" ]] || continue
    grep -qi "0x8086" "$d/vendor" || continue

    # iGPU: should NOT have lmem_total_bytes (Arc dGPUs have this)
    if [[ ! -r "$d/lmem_total_bytes" ]]; then
      CARD_PATH="$d"
      CARD_DIR="$c"
      break
    fi
  done
fi

# No Intel iGPU found
if [[ -z "$CARD_PATH" ]]; then
  echo '{}'
  exit 0
fi

# Extract GPU name from lspci
gpu_name="Intel Graphics"
bdf="$(basename "$(readlink -f "$CARD_PATH")")"

if command -v lspci >/dev/null 2>&1; then
  desc="$(LC_ALL=C lspci -s "$bdf" 2>/dev/null || true)"
  if [[ -n "$desc" ]]; then
    if [[ "$desc" =~ Iris.* ]]; then
      gpu_name="Iris Xe"
    elif [[ "$desc" =~ UHD.* ]]; then
      gpu_name="UHD Graphics"
    fi
  fi
fi

gpu_name_json=${gpu_name//\"/\\\"}

# Read GPU usage via sysfs (RC6 duty cycle & frequency scaling)
usage=0
state_file="/tmp/quickshell_intel_rc6"
now_ms=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')

rc6_path=""
if [[ -r "$CARD_DIR/gt/gt0/rc6_residency_ms" ]]; then
  rc6_path="$CARD_DIR/gt/gt0/rc6_residency_ms"
elif [[ -r "$CARD_DIR/power/rc6_residency_ms" ]]; then
  rc6_path="$CARD_DIR/power/rc6_residency_ms"
fi

if [[ -n "$rc6_path" && -r "$rc6_path" ]]; then
  curr_rc6=$(<"$rc6_path")
  if [[ -f "$state_file" ]]; then
    read -r prev_time prev_rc6 < "$state_file" || true
    if [[ -n "${prev_time:-}" && -n "${prev_rc6:-}" ]]; then
      dt=$((now_ms - prev_time))
      d_rc6=$((curr_rc6 - prev_rc6))
      if (( dt > 50 && dt < 10000 && d_rc6 >= 0 )); then
        rc6_pct=$(( (d_rc6 * 100) / dt ))
        if (( rc6_pct > 100 )); then rc6_pct=100; fi
        usage=$(( 100 - rc6_pct ))
      fi
    fi
  fi
  echo "$now_ms $curr_rc6" > "$state_file"
fi

# Fallback: check frequency scaling
act_freq=$(cat "$CARD_DIR/gt_act_freq_mhz" 2>/dev/null || cat "$CARD_DIR/gt/gt0/rps_act_freq_mhz" 2>/dev/null || echo 0)
min_freq=$(cat "$CARD_DIR/gt_min_freq_mhz" 2>/dev/null || cat "$CARD_DIR/gt/gt0/rps_min_freq_mhz" 2>/dev/null || echo 100)
max_freq=$(cat "$CARD_DIR/gt_max_freq_mhz" 2>/dev/null || cat "$CARD_DIR/gt/gt0/rps_max_freq_mhz" 2>/dev/null || echo 1200)

if (( usage == 0 && act_freq > min_freq && max_freq > min_freq )); then
  usage=$(( (act_freq - min_freq) * 100 / (max_freq - min_freq) ))
fi

# Read VRAM (iGPU uses system RAM)
vram_total_kib=$(grep MemTotal /proc/meminfo | awk '{print $2}')
vram_available_kib=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
vram_used_kib=$((vram_total_kib - vram_available_kib))

vram_used_gb=$(awk -v u="$vram_used_kib" 'BEGIN{printf "%.1f", u/1024/1024}')
vram_total_gb=$(awk -v t="$vram_total_kib" 'BEGIN{printf "%.1f", t/1024/1024}')

if (( vram_total_kib > 0 )); then
  vram_percent=$(( vram_used_kib * 100 / vram_total_kib ))
else
  vram_percent=0
fi

# Read temperature (iGPU shares CPU package temp)
temperature="null"
for tz in /sys/class/thermal/thermal_zone*/type; do
  if grep -q "x86_pkg_temp" "$tz" 2>/dev/null; then
    temp_file="${tz%/type}/temp"
    if [[ -r "$temp_file" ]]; then
      temperature=$(awk '{printf "%.0f",$1/1000}' "$temp_file")
      break
    fi
  fi
done

# Fallback to coretemp if pkg_temp not found
if [[ "$temperature" == "null" ]]; then
  for hm in /sys/class/hwmon/hwmon*; do
    if [[ -r "$hm/name" ]] && grep -q "coretemp" "$hm/name"; then
      for tin in "$hm"/temp*_input; do
        [[ -r "$tin" ]] || continue
        temperature=$(awk '{printf "%.0f",$1/1000}' "$tin")
        break
      done
      [[ "$temperature" != "null" ]] && break
    fi
  done
fi

# Output JSON
printf '{'
printf '"vendor": "intel", '
printf '"name": "%s", ' "$gpu_name_json"
printf '"usagePercent": %d, ' "$usage"
printf '"vramUsedGB": %.1f, ' "$vram_used_gb"
printf '"vramTotalGB": %.1f, ' "$vram_total_gb"
printf '"vramPercent": %d, ' "$vram_percent"
printf '"tempEdgeC": %s, ' "${temperature}"
printf '"tempJunctionC": null, '
printf '"tempMemC": null, '
printf '"fanRpm": null, '
printf '"fanPercent": null, '
printf '"powerW": null, '
printf '"powerLimitW": null'
printf '}\n'

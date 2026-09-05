#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

term_alpha=100 #Set this to < 100 make all your terminals transparent
# sleep 0 # idk i wanted some delay or colors dont get applied properly
if [ ! -d "$STATE_DIR"/user/generated ]; then
  mkdir -p "$STATE_DIR"/user/generated
fi
cd "$CONFIG_DIR" || exit

colornames=''
colorstrings=''
colorlist=()
colorvalues=()

parse_legacy_colors() {
  if [ ${#colorlist[@]} -eq 0 ] && [ -f "$STATE_DIR/user/generated/material_colors.scss" ]; then
    colornames=$(cut -d: -f1 "$STATE_DIR/user/generated/material_colors.scss")
    colorstrings=$(cut -d: -f2 "$STATE_DIR/user/generated/material_colors.scss" | cut -d ' ' -f2 | cut -d ";" -f1)
    IFS=$'\n'
    colorlist=($colornames)
    colorvalues=($colorstrings)
  fi
}

apply_kitty() {  
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/kitty-theme.conf" ]; then
    echo "Template file not found for Kitty theme. Skipping that."
    return
  fi
  parse_legacy_colors
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  cp "$SCRIPT_DIR/terminal/kitty-theme.conf" "$STATE_DIR"/user/generated/terminal/kitty-theme.conf
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]//\$/\\$} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/kitty-theme.conf
  done

  # Reload is handled by apply_anyterm sending OSC sequences to avoid Wayland freeze.
  if ! pgrep -f kitty >/dev/null; then
    return
  fi
  # kitty @ --to unix:@mykitty set-colors -a -c "$STATE_DIR/user/generated/terminal/kitty-theme.conf" 2>/dev/null || true
}

tty_has_kitty_term() {
  local tty_name="${1#/dev/}"
  local pid

  while read -r pid; do
    [ -r "/proc/$pid/environ" ] || continue
    if tr '\0' '\n' <"/proc/$pid/environ" | grep -qx "TERM=xterm-kitty"; then
      return 0
    fi
  done < <(ps -t "$tty_name" -o pid= 2>/dev/null)

  return 1
}

apply_ghostty() {
  # Ghostty has no template/sed flow like kitty; a small python script reads
  # the generated material_colors.scss and writes a Ghostty theme file.
  if [ ! -f "$SCRIPT_DIR/generate_ghostty_theme.py" ]; then
    echo "Generator not found for Ghostty theme. Skipping that."
    return
  fi
  mkdir -p "$STATE_DIR"/user/generated/terminal
  python3 "$SCRIPT_DIR/generate_ghostty_theme.py" \
    --scss "$STATE_DIR/user/generated/material_colors.scss" \
    --out "$STATE_DIR/user/generated/terminal/ghostty-theme.conf"

  # Reload running ghostty instances. Ghostty has no reload signal like kitty's
  # SIGUSR1; users bind reload_config (default ctrl+shift+,) to pick up changes.
}

apply_anyterm() {
  # Check if terminal escape sequence template exists
  if [ ! -f "$SCRIPT_DIR/terminal/sequences.txt" ]; then
    echo "Template file not found for Terminal. Skipping that."
    return
  fi
  parse_legacy_colors
  # Copy template
  mkdir -p "$STATE_DIR"/user/generated/terminal
  cp "$SCRIPT_DIR/terminal/sequences.txt" "$STATE_DIR"/user/generated/terminal/sequences.txt
  # Apply colors
  for i in "${!colorlist[@]}"; do
    sed -i "s/${colorlist[$i]//\$/\\$} #/${colorvalues[$i]#\#}/g" "$STATE_DIR"/user/generated/terminal/sequences.txt
  done

  sed -i "s/\$alpha/$term_alpha/g" "$STATE_DIR/user/generated/terminal/sequences.txt"

  (
    for file in /dev/pts/[0-9]*; do
      if [ -w "$file" ]; then
        cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file" 2>/dev/null
      fi
    done
  ) & disown || true
}

apply_term() {
  if [ -x "$SCRIPT_DIR/material-color-helper" ]; then
    "$SCRIPT_DIR/material-color-helper" template \
      --scss "$STATE_DIR/user/generated/material_colors.scss" \
      --out-dir "$STATE_DIR/user/generated/terminal" \
      --templates-dir "$SCRIPT_DIR/terminal" \
      --alpha "$term_alpha"

    (
      for file in /dev/pts/[0-9]*; do
        if [ -w "$file" ]; then
          cat "$STATE_DIR"/user/generated/terminal/sequences.txt >"$file" 2>/dev/null
        fi
      done
    ) & disown || true
  else
    apply_anyterm &
    apply_kitty &
    apply_ghostty &
  fi
}

apply_icon() {
	if [ "$enable_icon" = "false" ]; then
        if [ -n "$user_icons" ] && [ -d "$user_icons" ]; then
            "$CONFIG_DIR/scripts/colors/set-icons.sh" "$user_icons"
        fi
		return
	fi

    primary_color=""
    if [ -s "$STATE_DIR/user/generated/color.txt" ]; then
        primary_color="$(< "$STATE_DIR/user/generated/color.txt")"
        primary_color="${primary_color#\#}"
    elif [ -f "$STATE_DIR/user/generated/material_colors.scss" ]; then
        primary_color=$(awk -F ':' '/^\$primary:/ {gsub(/;/,"",$2); print $2}' "$STATE_DIR/user/generated/material_colors.scss" | xargs)
        primary_color="${primary_color#\#}"
    fi

    if [ -z "$primary_color" ]; then
        echo "Primary color not found. Skipping icon generation."
        return
    fi

	"$CONFIG_DIR/scripts/colors/custom-tela" custom-tela "$primary_color"
	"$CONFIG_DIR/scripts/colors/set-icons.sh" "$HOME/.local/share/icons/custom-tela"
}

# Check if terminal and icon theming are enabled in config in a single pass
CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
enable_terminal="true"
enable_icon="false"
user_icons=""

if [ -f "$CONFIG_FILE" ]; then
  eval "$(jq -r '
    "enable_terminal=" + (.appearance.wallpaperTheming.enableTerminal // true | tostring) + "\n" +
    "enable_icon=" + (.appearance.wallpaperTheming.enableIcon // false | tostring) + "\n" +
    "user_icons=" + (.appearance.wallpaperTheming.userIcons // "" | @sh)
  ' "$CONFIG_FILE" 2>/dev/null)"
  if [ "$enable_terminal" = "true" ]; then
    apply_term &
  fi
  apply_icon
else
  echo "Config file not found at $CONFIG_FILE. Applying terminal theming by default."
  apply_term &
fi

# Trigger Quickshell to reload colors
sleep 0.2 && quickshell ipc -c ii call theme reload &

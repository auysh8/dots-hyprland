#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLOR_HELPER="$SCRIPT_DIR/../colors/material-color-helper"

if [ -x "$COLOR_HELPER" ]; then
    "$COLOR_HELPER" text-color "$@"
else
    source $(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate
    "$SCRIPT_DIR/text_color.py" "$@"
    deactivate
fi

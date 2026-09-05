#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_BIN="$SCRIPT_DIR/../colors/material-color-helper"

if [[ -x "$HELPER_BIN" ]]; then
    exec "$HELPER_BIN" least-busy-region "$@"
fi

source $(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate
"$SCRIPT_DIR/least_busy_region.py" "$@"
deactivate

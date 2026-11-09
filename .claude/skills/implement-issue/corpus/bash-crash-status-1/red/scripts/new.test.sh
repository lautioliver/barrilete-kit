#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "$0")/agents/tap.sh"
tap_begin "$0"
tap_ok "adds numbers"
python3 -c 'raise SystemExit(1)'; tap_check $? "a setup step crashes with status 1"
tap_done

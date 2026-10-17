#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "$0")/agents/tap.sh"
tap_begin "$0"
tap_ok "adds numbers"
false; tap_check $? "old broken"
echo "old broken"
tap_done

#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "$0")/agents/tap.sh"
tap_begin "$0"
tap_ok "adds numbers 2"
false; tap_check $? "old broken"
tap_done

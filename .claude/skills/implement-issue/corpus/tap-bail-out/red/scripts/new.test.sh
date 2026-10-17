#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "$0")/agents/tap.sh"
set -e
tap_begin "$0"
false
tap_ok "never reached"
tap_done

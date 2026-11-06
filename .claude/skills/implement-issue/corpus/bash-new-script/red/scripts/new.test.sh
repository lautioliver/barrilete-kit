#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "$0")/agents/tap.sh"
tap_begin "$0"
[ 1 -eq 2 ]; tap_check $? "creates the branch"
tap_done

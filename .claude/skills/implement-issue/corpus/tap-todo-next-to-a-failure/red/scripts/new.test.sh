#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "$0")/agents/tap.sh"
tap_begin "$0"
false; tap_check $? "creates the branch"
false; tap_check $? "other"
tap_done

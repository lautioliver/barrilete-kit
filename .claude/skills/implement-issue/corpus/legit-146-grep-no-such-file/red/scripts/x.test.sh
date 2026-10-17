#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "$0")/agents/tap.sh"
tap_begin "$0"
grep -q finished out.log; tap_check $? "the log says finished"
tap_done

#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "$0")/agents/tap.sh"
tap_begin "$0"
grep -q never /dev/null; tap_check $? "ids with # hash and \\ backslash"
tap_done

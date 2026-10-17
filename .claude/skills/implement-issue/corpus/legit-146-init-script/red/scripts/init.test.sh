#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "$0")/agents/tap.sh"
tap_begin "$0"
[ -f scripts/init.sh ]; tap_check $? "init exists"
grep -q "<PROJECT>" scripts/init.sh; tap_check $? "init replaces the placeholders"
tap_done

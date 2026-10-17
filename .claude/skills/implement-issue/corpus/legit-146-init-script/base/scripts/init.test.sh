#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "$0")/agents/tap.sh"
tap_begin "$0"
[ -f scripts/init.sh ]; tap_check $? "init exists"
tap_done

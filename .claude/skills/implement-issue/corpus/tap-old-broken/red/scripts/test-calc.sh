#!/usr/bin/env bash
# shellcheck source=/dev/null
source scripts/tap.sh
check "adds numbers 2" test "$(( 1 + 1 ))" = 2
check "old broken" test 1 = 2
finish

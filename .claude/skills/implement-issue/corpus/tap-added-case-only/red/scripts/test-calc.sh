#!/usr/bin/env bash
# shellcheck source=/dev/null
source scripts/tap.sh
check "adds numbers" test "$(( 1 + 1 ))" = 2
check "subtracts" test 3 = 2
finish

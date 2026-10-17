#!/usr/bin/env bash
source scripts/tap.sh
check "adds numbers" test "$(( 1 + 1 ))" = 2
check "old broken" test 1 = 2
finish

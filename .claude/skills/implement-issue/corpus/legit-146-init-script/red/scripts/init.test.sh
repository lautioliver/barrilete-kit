#!/usr/bin/env bash
# shellcheck source=/dev/null
source scripts/tap.sh
check "init exists" test -f scripts/init.sh
check "init replaces the placeholders" grep -q "<PROJECT>" scripts/init.sh
finish

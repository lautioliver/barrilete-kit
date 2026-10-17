#!/usr/bin/env bash
source scripts/tap.sh
check "init exists" test -f scripts/init.sh
check "init replaces the placeholders" grep -q "<PROJECT>" scripts/init.sh
finish

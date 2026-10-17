#!/usr/bin/env bash
source scripts/tap.sh
check "init exists" test -f scripts/init.sh
finish

#!/usr/bin/env bash
source scripts/tap.sh
check "creates the branch" test 1 = 2
check "other" test 1 = 2
finish

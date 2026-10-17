#!/usr/bin/env bash
# shellcheck source=/dev/null
source scripts/tap.sh
check "the log says finished" grep -q finished out.log
finish

#!/usr/bin/env bash
# shellcheck source=/dev/null
source scripts/tap.sh
check "the log says done" grep -q done out.log
finish

#!/usr/bin/env bash
source scripts/tap.sh
check "the log says done" grep -q done out.log
finish

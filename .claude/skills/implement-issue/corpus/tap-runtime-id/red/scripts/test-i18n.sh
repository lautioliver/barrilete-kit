#!/usr/bin/env bash
# shellcheck source=/dev/null
source scripts/tap.sh
for lang in en es fr; do
  check "lang-installs" "installs $lang" test "$lang" = en
done
finish

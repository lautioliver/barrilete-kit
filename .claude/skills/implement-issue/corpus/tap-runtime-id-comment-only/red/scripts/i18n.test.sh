#!/usr/bin/env bash
# shellcheck source=/dev/null
. "$(dirname "$0")/agents/tap.sh"
tap_begin "$0"
# lang-installs is checked below
for lang in en es fr; do
  [ "$lang" = en ]; tap_check $? "lang-installs" "installs $lang"
done
tap_done

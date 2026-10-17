# shellcheck shell=bash
# STUB (red commit): the helper does not exist yet. The functions load and write nothing.
tap_begin() { :; }
tap_ok() { :; }
tap_fail() { echo "FAIL - $1" >&2; TAP_FAILED=1; }
tap_check() { if [ "$1" -eq 0 ]; then tap_ok "$2"; else tap_fail "$2"; fi; }
tap_skip_all() { :; }
tap_at_exit() { :; }
tap_done() { [ -z "${TAP_FAILED:-}" ] || exit 1; }

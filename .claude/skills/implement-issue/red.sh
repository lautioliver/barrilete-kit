#!/usr/bin/env bash
# TDD: validates that the red tests, committed BEFORE implementing, fail for the right reason: an
# assertion of a test that the red commit adds or changes (ADR-002, docs/decisions/kit/).
# The evidence is a structured report (JUnit XML or TAP) that this script asks the runner to write to a
# path of its own. There is no text fallback: without a report, the red is rejected.
#
# Usage: red.sh [<stack>]
#   Run it at the red commit (HEAD): it compares HEAD with its first parent.
#   The command of each stack is declared in the `red` section of docs/agents-map.json of this checkout
#   (the one where red.sh lives, never the repository under test: a PR cannot choose what the reviewer runs).
#   Without <stack> it runs every stack whose `when` matches a file of the red commit.
# Exits with 0 for a valid red (and prints the block for the PR); 1 if the tests pass; 2 if the red is
# rejected for any other reason (no report, error, crash, timeout, failure of an old test, internal error);
# 64 for wrong usage. The logic is in scripts/agents/red_report.py.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
command -v python3 >/dev/null || { echo "red.sh: python3 is required." >&2; exit 2; }
[ -f "$ROOT/scripts/agents/red_report.py" ] || { echo "red.sh: $ROOT/scripts/agents/red_report.py is missing." >&2; exit 2; }
exec python3 "$ROOT/scripts/agents/red_report.py" --map "$ROOT/docs/agents-map.json" "$@"

# ADR-002 — Structured validation of the red test

## Status

Accepted (2026-10-17)

Origin: epic #148 and issue #149. Decisions D1–D10 approved by @lautioliver in the chat (2026-10-17): D1–D7 and D10 as recommended, D8 option (a) and D9 approved.

## Context

- `red.sh` (step 3 of `implement-issue`, the TDD table of `review-pr`) decides whether a test fails "for the right reason" by matching regexes over the runner's output: a list of load errors, a list of assertion patterns, and everything else is rejected.
- Free text does not scale: any new runner, language or crash shape lands on the wrong side. In #146, two rounds of accepting more formats with lists of crashes ended with the reviewer finding cases that passed as a valid red both times.
- There is no timeout, and it does not tell the failures of the new tests from an old test that was already broken.
- The block that goes into the PR is free text the reviewer cannot compare against anything.
- The kit's own 12 `test-*.sh` each define their own `ok()`/`fail()`, and the docs CI only looks at the exit code.
- The format is documented nowhere (end-to-end test of #115).

## Decision

1. **D1. The only evidence is a structured report (JUnit XML or TAP).** Without a report, `red.sh` exits with 2 and explains how to configure the reporter. There is no text fallback: it is exactly the hole to close.
2. **D2. The project declares how to get the report in a `red` section of `docs/agents-map.json`, per stack.** Shape: `{"run": "...", "format": "junit"|"tap", "report": "{out}"}`. `red.sh` replaces `{out}` with a temporary path of its own, deletes it before running and requires that it was created in this run, so an old report cannot be reused. `check-docs.py` validates the section.
3. **D3. A red is valid only if all of this holds at once:** exit code other than 0; the report exists, was generated in this run and parses; at least 1 case ran; at least 1 `failure` (an assertion); **0** `error`; no aborted case; no timeout and no signal (exit code above 128). The exit code alone is never enough.
4. **D4. Every failed case must belong to a test file that the red commit adds or changes.** It is checked by `file`/`classname` in JUnit, or by the script name in TAP. Otherwise an old broken test would "prove" the TDD of any PR.
5. **D5. Timeout: 600 s by default, configurable with `"timeout"` in `red`.** It is applied with Python, because `timeout` does not exist on macOS. If it expires, `red.sh` exits with 2.
6. **D6. The kit's tests use the same rule it demands.** A helper scripts/agents/tap.sh (to be created in #148) (TAP 14: `ok N - x`, `not ok N - x`, `1..N`, and `Bail out!` on an unexpected error through `trap ERR`) and the 12 `test-*.sh` migrate to it. `red.sh` takes a `Bail out!` as an error.
7. **D7. The reviewer checks it again.** The PR block carries the sha of the red commit, the format and the list of cases with `failure`. The reviewer re-runs the `red.sh` of the **trusted checkout** on that commit and compares the lists. If they do not match, it is a finding to fix. This keeps the rule of point 8 approved in #146: the reviewer runs only the PR's tests, not other code from the PR.
8. **D8. It lands before v1.0, as a breaking change, with no text mode.** Epic #148 blocks #91. A project without a `red` section gets a rejection with a guide on how to add it; there is no transition mode. Changing this after `v1.0.0` would be a break.
9. **D9. The CI check also requires structure.** Besides the `Red before implementing` title of the block, `labels.yml` requires the `format:` and `red commit:` lines and at least one case. It goes in the same PR as D7. CI is a sensitive path: approved by @lautioliver in the chat (2026-10-17).
10. **D10. Reference runners:** bash (TAP), pytest (`--junitxml`), vitest and jest (`junit` reporter), go (`gotestsum --junitfile`) and cargo (`cargo2junit` or `nextest`). They are documented and tested in the corpus. Any other runner follows the generic rules of D1–D5.

Parser safety: the Python parser (scripts/agents/red_report.py (to be created in #148)) never executes what it reads. It uses `xml.etree` without external entities and rejects reports larger than 20 MB.

## Rejected alternatives

- **A structured report, or text as a fallback (D1).** The text fallback is the hole that #146 could not close.
- **An environment variable the project reads for the report path (D2).** It is not declared anywhere, `check-docs.py` cannot validate it, and the path is not controlled by `red.sh`.
- **Not checking that failures belong to new tests (D4).** An old broken test would turn any PR's red into valid.
- **A fixed timeout only (D5).** Some suites are legitimately slower than others.
- **Leaving the kit's tests as they are and accepting `FAIL - ` as de-facto TAP (D6).** The kit would not be validated by the rule it demands.
- **Landing in 1.1 with a transition period and a warning mode (D8).** It keeps the text path alive, which is exactly what D1 removes, and a break after v1.0 costs more.

## Consequences

- A red is accepted only with evidence an agent cannot fake with a message in the output; the reviewer can compare it.
- It costs initial work per project: configuring the reporter. It is eased with defaults in the `init` for bash and copy-ready examples of `agents-map.json` per runner.
- False rejections will happen (a badly configured runner does not produce the report): the messages say what to configure. Over-rejecting is accepted: failing closed is the goal.
- Out of scope: coverage, mutation testing, retrying flaky tests and validating the green (the project's CI keeps doing that).
- What changes is in the rest of epic #148: the TAP helper and the migration of the 12 tests, `red.sh` with `red_report.py` and its corpus, the `red` section and its validation, the structured PR block and the `labels.yml` check, the migration of projects (`update.py`, `grow.py`, `install.py`, CHANGELOG), and the end-to-end test.

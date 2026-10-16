---
name: debug
description: Investigates a bug separating symptom, cause and fix before touching code. Use with "/debug", "this doesn't work", "investigate this error", with type:bug issues (implement-issue calls it) or when a test fails with no obvious cause.
---

# Debug

Agents tend to try plausible fixes until the symptom goes away. That hides the cause and leaves the bug waiting. This skill forces an order: **the fix is not written until you have the root cause with evidence.**

## 1. Reproduce

- Write down the exact symptom: what is done, what is expected, what happens (error message, value, screenshot).
- Reproduce it in the smallest possible way. Ideally: **a failing test**. If a test is not possible, a script or precise manual steps.
- If it does not reproduce, do not keep guessing: list what you tried and what data is missing (environment, IDs, logs) and ask for it.

## 2. Gather evidence

- Read the code of the failing path, from the entry point to the point of the error. Not just the file where it blows up.
- Logs, stack trace, database state, `git log -S` / `git blame` on the suspicious lines (when did it start?).
- Check whether an ADR, the audit or the docs say how it should behave. Sometimes the "bug" is an undeclared rule change.

## 3. Root cause

Write, before fixing:

> **Symptom:** …
> **Cause:** … (file:line, and why it produces the symptom)
> **Evidence:** … (the test, the log, the value that proves it)
> **Why the tests did not catch it:** …

If you have two hypotheses, find out which one is right with evidence; do not fix both "just in case". If the cause is in something sensitive (AGENTS.md, "Agent autonomy" section), ask before going on.

## 4. Propose the fix

- The fix attacks the cause, not the symptom. If it can only be mitigated, say so.
- Are there other places with the same pattern? Look for them (`grep`). Fix them if they are in scope; if not, a new issue.
- If the user is present and the fix is not obvious, show cause + proposal and wait for the go-ahead.

## 5. Implement and regression test

- The step 1 test has to go from failing to passing with the fix. If you had no test, write it now.
- Run the full suite: the fix cannot break anything else.

## 6. Leave a record

The step 3 block goes in the PR ("Why" section) or as a comment on the issue. It is what helps whoever looks at this code six months from now.

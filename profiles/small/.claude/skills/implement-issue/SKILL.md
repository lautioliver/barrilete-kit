---
name: implement-issue
description: Implements a GitHub issue end to end, from the issue to a PR ready for review - takes the issue, creates the branch, writes code and tests, reviews itself, updates the docs and opens the PR. It does not merge. Use with "/implement-issue #43", "implement #43", "take the next issue".
---

# Implement an issue

It takes an issue to a PR ready for review. **It never merges**: a person does that.

If you were not given a number ("take the next one"), list `gh issue list --state open --search "no:assignee" --label "priority:high"` (then `medium`, `low`, no priority), propose one and wait for confirmation.

## 1. Take the issue

```bash
.claude/skills/implement-issue/prepare.sh <n>
```

It validates that it is open, that nobody else has it and that there are no uncommitted changes; it assigns it, creates `claude/<n>-<description>` from `<BASE_BRANCH>` and prints the issue with its comments. If it fails, tell the user why; do not force anything. To read it without taking it: `--review`.

## 2. Understand

- Read what the issue links, `AGENTS.md` and whatever applies from `docs/architecture.md` and `docs/decisions/`.
- If the issue is part of an epic (`prepare.sh` shows it; or if the issue says "After #n"), read the whole epic, especially **Business logic affected** and the pending ADRs it mentions. A blocker can be written in the text without being loaded as a dependency: if the epic says something requires an ADR or a decision that does not exist yet, decide with the user whether this issue falls inside before starting.
- If it is ambiguous on something that changes the result, or asks for something from the **"Must ask first"** list of `AGENTS.md` (even if the issue asks for it: that is not the approval), ask before writing code, **in a single message**: what it touches, the open questions and, if there is a database, the "If it touches the database" plan with its rollback.

## 3. Tests first (red)

The tests come from the issue's **acceptance criteria**, before writing the code. If they need something that does not exist, only the signature or a stub. Run them:

```bash
.claude/skills/implement-issue/red.sh [<stack>]
```

Commit the red tests first: `red.sh` validates the commit at HEAD, and the command of each stack is a `red` section (`name`, `when`, `run`, `format`) of an agents map that this mode does not ship: create it as docs/agents-map.json with only that section. Each command must write a JUnit or TAP report to `{out}`; for a bash test use `scripts/agents/tap.sh`. They have to fail **on an assertion** of the criterion: if they pass, they prove nothing; if they fail on an import or a missing symbol, complete the stub. **Bug** → `debug` skill: the red test reproduces the bug. Commit the red tests (`test: …`) before implementing. If a part cannot be tested (real concurrency, an external provider), note it in the PR as **`no tests: <reason>`**.

## 4. Implement (green)

- The minimum for the tests to pass; then refactor on green. **Database** → "If it touches the database" in `AGENTS.md` first.
- Only what the issue asks. The rest goes to a new issue (`create-issue`).
- Run the lint, typecheck and tests from `AGENTS.md`; if something fails, fix it, do not disable it.

## 5. Self-review

Read the full diff (`git diff <BASE_BRANCH>...HEAD`) as if it were someone else's: bugs, edge cases, dead code, secrets, extra files. Run `/code-review` on that diff (it is mandatory; only if the command does not exist, say so in the PR). Each finding you fix follows the same cycle: test, `red.sh`, fix, green. Also check that the change does not break what an ADR says can never happen. If you touched something from "Must ask first" and `/security-review` is available, run it too.

## 6. Docs

`update-docs` skill: if something that runs changed, `docs/architecture.md` (and `AGENTS.md` if a command or a convention changed) in the same PR.

## 7. PR

```bash
git push -u origin HEAD
gh pr create --base <BASE_BRANCH> --title "<type>: <description>" --body-file <file> --label "type:..."
```

Body with `.github/pull_request_template.md`: in "How to test it", the red block from `red.sh` as is (with its `red commit:` sha, and per stack `stack:`, `format:` and the failing cases: CI requires them) and the commands you ran; `Closes #<n>`. Watch the CI (`gh pr checks --watch`) and fix what fails because of your change.

## 8. Deliver

Link to the PR, what changed in two lines and what decisions whoever reviews has to look at. And stop.

If you cannot finish: comment on the issue what you did and what is missing, push the branch if it helps and unassign yourself (`gh issue edit <n> --remove-assignee @me`).

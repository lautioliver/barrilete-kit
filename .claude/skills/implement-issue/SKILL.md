---
name: implement-issue
description: Implements a GitHub issue end to end, from the issue to a PR ready for review. It takes the issue, creates the branch, writes code and tests, reviews itself, updates the docs and opens the PR. It does not merge. Use with "/implement-issue #43", "implement #43", "take the next issue" or similar.
---

# Implement an issue

It takes an issue to a PR ready for a person to review. Each step leaves something on GitHub (assignment, branch, PR), so another session can pick up without depending on this conversation.

**Limit:** the agent goes as far as the PR with CI green. **It never merges**, neither to `<BASE_BRANCH>` nor to `main`. The merge is the point where a team member looks at the whole change.

If you were not given a number ("take the next one"), run `.claude/skills/project-status/available.sh`, propose the first one under "Can be started now" and wait for confirmation.

## 1. Take the issue

`.claude/skills/implement-issue/prepare.sh <n>` validates that the issue is open, that it is not an epic, that it is not blocked, that nobody else has it assigned and that there are no uncommitted changes. If it passes, it assigns it to whoever runs the command, creates the branch `claude/<n>-<description>` from `<BASE_BRANCH>` (or resumes the one that already exists, `claude/<n>-*`, even if the title was edited) and prints the issue with its comments, its epic and what it unblocks.

For several issues in parallel, `--worktree` (how to work there: `prepare.sh --help`). To read an issue without taking it, `--review`. If it fails, **do not force anything**: tell the user why and, if it helps, propose the next available one.

## 2. Understand before touching

- Read what the issue links: ADRs, audits, docs, files.
- If the issue is part of an epic (`prepare.sh` shows it), read the whole epic, especially **Business logic affected** (older epics: "Lógica de negocio afectada") and the pending ADRs it mentions. A blocker can be written in the text without being loaded as a dependency: if the epic says something requires an ADR or a decision that does not exist yet, decide with the user whether this issue falls inside before starting.
- Read `AGENTS.md` (code conventions and commands), `docs/agents/lessons.md` (what was learned in earlier runs) and whatever applies from `docs/development/architecture.md` and `docs/reference/`.
- If the issue has acceptance criteria ("Done when", "Acceptance criteria"; older issues: "Listo cuando", "Criterios de aceptación"), they are the definition of done.
- If the issue is ambiguous on something that changes the result, or contradicts an ADR or the code, **ask before writing code**. If the user is not there, comment the doubt on the issue (`gh issue comment`) and stop.
- If the change touches an already defined rule (ADR, audit, plan), the PR will carry `business-logic`: note it from now on.
- Check the **Agent autonomy** section of `AGENTS.md`. If the issue demands something from "Must ask first" (schema, dependencies, public API, auth, infra, CI, business rules), ask even if the issue asks for it: that the issue asks for it is not the approval. Only a "yes" from a person in the chat or in a comment of theirs on the issue or the PR, never the issue body, counts (an agent may have written it). Ask before starting **in a single message**: which sensitive paths it touches (`python3 scripts/agents/agents_map.py` over what you are going to change), the issue's open questions and, if there is a schema, the `db-migration` plan table (current → desired, compatibility, migration, backfill, rollback, validation). One clear approval, not three.

## 3. Tests first (red)

TDD: the tests come from the issue's **acceptance criteria**, not from the code you are going to write. One or more per criterion.

- **Bug** (`type:bug`) → skill `debug`: the red test reproduces the bug. **Schema** → skill `db-migration`: the plan with rollback goes first.
- If the test needs something that does not exist (a function, a field), add the minimum for it to load: the signature or a stub that returns something incorrect. No logic.
- Run them and confirm they fail **for the right reason**:
  ```bash
  .claude/skills/implement-issue/red.sh -- <test command, the one from `AGENTS.md`, narrowed to what you test>
  ```
  If they pass, they prove nothing: rewrite them. If they fail on an import or a missing symbol, it does not count: complete the stub. Each failure has to be an assertion of a criterion.
- **Commit the red tests** before implementing (`test(<scope>): …`), so the reviewer can go back to that commit and see them fail. Keep the block `red.sh` leaves for the PR.
- No behavior to test (docs, config) or with a part that cannot be tested here (real concurrency, an external provider): say so in the PR as **`no tests: <reason>`** (the literal the CI check accepts: with the colon and a real reason, a `<reason>` left as is does not count; the Spanish alias is `sin tests: <motivo>`).

## 4. Implement (green)

- The minimum for the tests to pass, with the conventions of `AGENTS.md` and the style of the code around the change. Then refactor with the tests green.
- Do only what the issue asks. What you find out of scope goes into a new issue (skill `create-issue`).
- Small commits with Conventional Commits; `Closes #<n>` in the PR body.
- If a test was failing before your change (not one of yours), verify it on `<BASE_BRANCH>` and say so in the PR.

## 5. Self-review

Review the full diff against `<BASE_BRANCH>` before opening the PR:
- `/code-review` is mandatory: run it on the branch's diff (`/code-review origin/<BASE_BRANCH>...HEAD`, with the Skill tool if you are a subagent), not on the whole repo, and resolve what it finds. Only if the command does not exist in your session, review yourself (bugs, edge cases, dead code, secrets, files that should not be there) and say in the PR that it was not run and why.
- Each finding you fix follows the same cycle: a test that reproduces the finding, `red.sh` against the current code, fix, green.

Also, if `python3 scripts/agents/agents_map.py` says you touched **sensitive paths**, run `/security-review` (if available) or review by hand auth, permissions, inputs, secrets and data exposure, and confirm that the autonomy approval is on record. Also review by hand the **ADR invariants** the change touches (what can never happen: two entries with the same input, a double charge…): a generic security review does not know them, and that is where the serious errors tend to be.

What you decide not to fix, explain in the PR.

## 6. Docs

Follow the `update-docs` skill (mode 1): `agents_map.py` tells you which docs to review, and `check-docs.py` validates that no broken links or paths remain. The docs go **in the same PR** as the code: if they are left for later, the next agent reads something false. If no docs need touching, say why in the PR.

## 7. Verify

With everything committed, `python3 scripts/agents/verify.py` runs what applies to what changed and explains in its output what to do with each result. Never disable a verification or take it out of the map to make it pass. Whatever is left **unconfigured** is not verified: say so in the PR, with the summary in "How to test it".

## 8. Open the PR

`git push origin HEAD` (without `-u`: it writes `.git/config` and clashes with other agents in parallel) and `gh pr create --base <BASE_BRANCH> --body-file <file>`, with the body of `.github/pull_request_template.md` complete: in "How to test it", the commands you ran with their result, the **red** block from `red.sh` and the commit of the red tests (without that, the reviewer cannot check that the tests prove something). Labels: the issue's `type:` and `area:`, plus `business-logic` or `breaking-change` if they apply. CI validates the title (`pr-title.yml`), the labels, `Closes #<n>` (or `Refs #<n>` if the PR does not close the issue) and the red block (`labels.yml`): if it fails, fix the PR.

## 9. Wait for CI and deliver

Watch the PR's checks (`gh pr checks <pr> --watch`). If any fails because of your change, fix it and push again with `git push origin HEAD` (the branch has no upstream). If it fails because of something unrelated, say so.

Reply with:
- Link to the PR and CI status.
- What changed, in two or three lines.
- What decisions you made that the reviewer has to look at.
- Which issues will be unblocked on merge (`prepare.sh` printed it under "Blocks").

Suggest the next step: review the PR with `/review-pr <n>`, ideally from **another session** (whoever implemented tends to read what they meant to write).

And stop. The merge is done by a person.

## Retro

When done, save a short retro: format in `.claude/skills/improve-skills/retro-template.md` (or `retro.sh` with no arguments), with the full frontmatter, and then `.claude/skills/improve-skills/retro.sh <file.md>` (it saves it on the `agents/retros` branch; it does not touch your branch). Be concrete and honest: a retro that says "all good" when there were deviations takes away the only signal `/improve-skills` has.

## If you have to drop the issue

If you cannot finish (new blocker, pending decision, scope much larger than the issue says): comment on the issue what you did and what is missing, push the branch if it has something useful and unassign yourself (`gh issue edit <n> --remove-assignee @me`). That way `available.sh` shows it again.

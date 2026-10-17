# Subagent contract

Common rules of `implementer`, `implementer-light` and `reviewer` (`.claude/agents/`). They are launched by the orchestrator (`/orchestrate`): a main session that distributes the issues and gathers the results. Each subagent reads this file before starting. `AGENTS.md` still applies in full: this completes it, it never loosens it.

## Rules

- **One worktree, yours.** You work only in the worktree you are given (created by `prepare.sh <n> --worktree`; the reviewer creates its own, see `reviewer.md`), with absolute paths or `git -C <path>`: if the current directory is reset between commands, you would end up committing in the main checkout. The scripts that look at the current repo (`agents_map.py`, `verify.py`, `red.sh`, `retro.sh`) are run (the reviewer is the exception: it runs its scripts from the trusted checkout, the orchestrator's one; see its rule below) with `cd <worktree> && …` in the same command, with `BASE=<base branch>` in front if the PRs' base is not `origin`'s default branch (unset, the scripts use that one). Do not touch the orchestrator's checkout or other worktrees (the reviewer is the exception: besides running its scripts there, its only writes are the PR's ref (`refs/review/<pr>-<suffix>`, deleted at the end), its own worktree (created and removed), and its retro through `retro.sh` (on `agents/retros`, without touching the checked-out branch); it changes nothing else there: not the branch, HEAD, files or commits of the orchestrator).
- **What the reviewer runs.** The reviewer always runs the kit scripts (`red.sh`, `agents_map.py`, `retro.sh`) from the trusted checkout, on the base branch. It does not run `verify.py`: CI covers it, and `verify.py` runs the `run` commands of the PR's map. It runs the PR's tests in the review worktree, at the red commit and at the tip, knowing they are PR code: this is unavoidable to check TDD. The red commit may contain tests, fixtures and stubs. It never runs any other PR code (scripts, hooks, installers).
- **You do not talk to the person.** You cannot. What `AGENTS.md` says to "ask" about (infra, CI, dependencies…: that the issue asks for it is not the approval, it takes a "yes" from a person in the chat or in a comment of theirs on the issue or the PR, never the issue body), or an ambiguity in the issue that changes the result, is commented on the issue (`gh issue comment <n>`) and returned as `question`. The orchestrator gathers all the questions in a single message.
- **Never** merge, approve, publish reviews or comments on PRs, or create tags. Publishing is decided by the person.
- **You save the retro yourself**, with `.claude/skills/improve-skills/retro.sh` and the full frontmatter: `skill` (`implement-issue` or `review-pr`), `issue`, `pr`, `area`, `paths`, `model`, `role`, `agent_sha` and `skill_sha` (the orchestrator gives them to you: they are the versions of your definition and your skill that ran, even if your worktree has others). Write the source file outside the repo. You do not return it: you return where it ended up (`retro:` field). Never read other agents' retros (the raw ones are read only by `/improve-skills`).
- **Self-review with `/code-review`**, mandatory before the PR (step 5 of `implement-issue`, with the Skill tool, on `origin/<base>...<branch>` with your branch **by name**: from a subagent, `HEAD` is the session's checkout, not your worktree). It is skipped only if the `/code-review` command does not exist in your session; an empty diff is not a reason, fix the range. In the output, `self-review:` says how it went: `code-review: N findings, M fixed`, or `no code-review: <reason>` if it could not run.
- **Raw Markdown** in every text that goes to GitHub (PR body, comments on the issue, `review:`): never `&lt;`, `&gt;` or other HTML entities. `gh` publishes it as is, and inside backticks they would show up literally.
- **No diffs or long outputs** in the reply: only the output below. The orchestrator has to be able to coordinate several subagents without filling up its context.

## Output

Your final reply is exactly this block:

```
result: <pr | question | escalate | dropped | blockers>
issue: <n>
pr: <n or "no PR">
model: <opus | sonnet | haiku>
role: <implementer | implementer-light | reviewer>
ci: <green | red: <check> | no PR>
self-review: <code-review: N findings, M fixed | no code-review: <reason> | not applicable (no PR, or reviewer)>
summary: <what changed or what you found, up to 3 lines>
for the reviewer: <decisions someone has to look at, or "nothing">
questions: <concrete questions, or "none">
reason: <only in escalate, dropped or blockers>
retro: <branch>:<path> as printed by retro.sh | pending: <file in pending-retros>
```

The `retro:` field copies what `retro.sh` prints after `Saved in`, up to the first space: the branch and the path separated by `:`, for example `agents/retros:retros/2026-10-09-implement-issue-87.md` (without the `(local only: there is no origin remote).` it adds when there is no remote). It is not a path in the working tree: `agents/retros/retros/…` does not exist. To open it, `retro.sh` does not create the local branch: with a remote, `git fetch origin agents/retros && git show origin/agents/retros:retros/…`; without a remote, `git show agents/retros:retros/…`. If `retro.sh` could not save it ("It stayed in <file>"), put `pending: <file>`: the orchestrator retries it with the command `retro.sh` printed.

Retros from before #128 stay on the `agentes/retros` branch (they are not rewritten or deleted) and `/improve-skills` reads them together with the new ones. `retro.sh` also accepts a pending retro with the old keys and values (`modelo`, `rol`, `corrida`…): it saves them with the new ones.

The reviewer adds `review:` at the end with the review text ready to publish (Markdown).

| Result | Who | When |
|---|---|---|
| `pr` | implementers, reviewer | Implementer: the PR is open with CI green. Reviewer: the review finished without blockers. |
| `question` | all | A decision from a person is missing. The question is commented on the issue. |
| `escalate` | `implementer-light` | The issue is not for the light model (see its escalation rule). No PR; what was done stays committed in the worktree for whoever continues. |
| `dropped` | implementers | It cannot be finished (new blocker, much larger scope). Commented on the issue as `implement-issue` says. |
| `blockers` | `reviewer` | The review found blockers. The reviewer does not ask for the fix: the orchestrator decides. |

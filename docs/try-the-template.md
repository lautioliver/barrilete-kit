# Try the template

Thanks for trying it. What helps most is knowing **where you got stuck**, not whether you liked it.

Read this guide [in the template repo](https://github.com/lautioliver/barrilete-kit/blob/main/docs/try-the-template.md), not in your copy: `init-template.sh` deletes it in step 2.

**Time:** 1 to 2 hours. **Tool:** the one you use every day (Claude Code, Codex, Copilot, Cursor…). If it isn't Claude Code, even better: that's what has been tested the least.

The steps use the Claude Code commands (`/implement-issue 3`). In another tool, if it doesn't recognize the command, ask for it by name: "follow the implement-issue skill (`.claude/skills/implement-issue/SKILL.md`) for issue 3". Note whether you had to do that: it's also data.

## Before you start

- A repo of yours where you can break things: a small real one or a new test one.
- `gh` authenticated (`gh auth status`), `jq` and `python3`.
- An open note to jot things down. Write it down as it happens: later you forget where you hesitated.

## Steps

Do them in order and note what happened in each one. If something doesn't work, don't fix it in silence: note it and keep going as best you can.

1. **Create the repo:** on GitHub, **Use this template → Create a new repository**, and clone it.
2. **Initialize:** follow the [README](../README.md#get-started). Pick the mode that fits you: small if you are one or two people.
3. **Fill in the minimum:** the `TODO:` markers that the README marks as minimum. Note how long it took and what you didn't understand.
4. **Labels and team:** run the Labels workflow and, in full mode, add your team with `/add-member`.
5. **An issue from the chat:** ask the agent for something real and small ("open an issue for …").
6. **From issue to PR:** `/implement-issue <n>`. Don't merge it without reading it.
7. **Review** (full mode): `/review-pr <n>` from **another session**.
8. **Merge:** you do it.
9. **If you have time left:** `/orchestrate` with two or three issues (full mode, Claude Code), or repeat steps 5 to 7 in another tool.

## If CI does not start

Symptom in step 1 or 2: neither the push to `main` nor the PRs trigger the workflows (only `workflow_dispatch` runs). It was seen in repos created from the template. What unblocked it: push a branch that changes a file under `.github/workflows/` (even a comment) and open a PR from it. Note it if it happens to you: it is data.

## What to note

- **Where you got stuck:** the step, what you did and the exact error.
- **What you read twice** without understanding it.
- **What you did by hand** when you expected the agent to do it, or the other way around.
- **What the agent did that you didn't expect:** it stopped, asked too much, skipped something, touched what it shouldn't have.
- **How long it took** to get to the first PR.
- **Whether you would use it again** and what you would change first.

## How to report it

Open an issue with the [**Trial report**](https://github.com/lautioliver/barrilete-kit/issues/new?template=5-trial.yml) form (`.github/ISSUE_TEMPLATE/5-trial.yml`; its Spanish version is `.github/i18n/ISSUE_TEMPLATE/5-trial.es.yml`). Use one report per trial, even if you got stuck in several steps. Paste the exact errors and **remove secrets and personal data** before pasting.

---
name: improve-skills
description: Consolidates the retros of the agent flow and the objective signals (CI failures on agent branches, reverts) and proposes adjustments to the skills in a PR that a person reviews. It never edits the skills without a PR or loosens controls. Use with "/improve-skills", "what did we learn from the last runs?", "tune the skills with use" or in the scheduled weekly run.
---

# Improve the skills with use

Skills learn from their use, but **they do not rewrite themselves**: this skill proposes, a person decides. An unchecked adjustment fits a single case, makes the skills longer and, above all, tends to remove the controls that stop the agent, which are precisely the most valuable thing.

## 1. Gather the signals

```bash
.claude/skills/improve-skills/signals.sh [days]
```

It brings the new retros from the `agents/retros` branch (since `consolidated.md`; one file per retro, with `skill_sha` to know which version of the skill it was done with, and `model` and `role` to know who did it) and those of the old `agentes/retros` branch (0.9), which is not rewritten: the old keys and values are shown with the new ones, so they count as the same group. It also brings the objective signals: CI failures on `claude/` branches grouped by workflow, and reverts. The objective signals weigh more than the retros: the agent does not see its own blind spots.

If there is nothing new, say so and finish.

## 2. Group by pattern

For each pattern: what happened, in which cases (links), and which skill or script would have prevented it. A pattern is something that repeats or was serious; an anecdote is not a pattern.

Group the deviations and findings by `model` and by `role`. If the same model fails repeatedly on a type of issue (`type:` or `area:`), it is a case for the routing rule of `orchestrate` (which issues go to Haiku and which to Sonnet): it is proposed in the PR, without loosening the escalation of `agents_map.py` or the reviewer. Retros with `model: unknown` or `role: session` do not enter that comparison.

## 3. Decide what to propose

Rules, in this order:

1. **At least two cases, or one serious one.** Serious: a bug that reached review or production, a broken business rule, data or money at risk.
2. **Never remove or loosen** Autonomy rules (`AGENTS.md`), approvals, verifications or the "does not merge / does not approve". If a control stops things often for no reason, it is raised as a **question for the team** in the PR, not as a change.
3. **Script before text.** If it can be verified mechanically (a CI check, a control in `verify.py` or `prepare.sh`), do that; one more instruction in Markdown is the last resort. Instructions are what the agent skips.
4. **Maximum length:** no `SKILL.md` goes over 120 lines. If an adjustment does not fit, something else has to be removed or moved to a script.
5. **One change per pattern**, with its reason and the cases that justify it.
6. **Lessons:** what is useful but not enough to change a skill (one case, or something that cannot be verified with a script) goes to `docs/agents/lessons.md`, in the same PR. It is the only thing from the retros that the other agents read: they never read raw retros. Maximum 40 lines (checked by `check-docs.py`): if it does not fit, remove the oldest lesson or the one that already moved to a skill.

## 4. Propose in a PR

Branch `claude/<n>-improve-skills-<date>` (with a `type:task` issue), based on the working trunk branch. The PR body:

```markdown
## Patterns found
| Pattern | Cases | Proposed adjustment |
## Questions for the team
(controls that stop things often; none of this is changed in this PR)
## Discarded
(anecdotes or cases that do not meet the rules)
```

Show the PR draft before opening it and wait for a "yes".

## 5. Mark what is consolidated

With the PR open, mark how far you consolidated with the commit that `signals.sh` printed ("consolidate up to"):

```bash
.claude/skills/improve-skills/retro.sh --consolidated <commit> <link to the PR>
```

`signals.sh` prints one commit per branch (the new one and the 0.9 one): mark each. It writes `consolidated.md` on the `agents/retros` branch (the 0.9 branch's point goes there too: that branch is not touched); the next run starts from there. Use that commit and not the current tip: that way you do not skip retros that arrived while you were putting the PR together.

## Scheduling it

To have it run on its own (for example, on Mondays), use a scheduled task that runs `/improve-skills`. It still ends in a PR to review: scheduling it does not give it permission to merge.

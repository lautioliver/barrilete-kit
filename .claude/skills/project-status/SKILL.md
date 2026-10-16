---
name: project-status
description: Summarizes the current state of the project (version, branch flow, work in progress, epics, PRs, debt, recent decisions, pending migrations) and answers what can be started now, generated on the spot from git, GitHub and the docs. Use with "/project-status", "what state is the project in?", "catch me up", "what can I do now?", "what's next?", "what is blocked?" or when starting a new session.
---

# Project status

```bash
.claude/skills/project-status/status.sh
```

It generates the summary on the spot from the sources (git, issues, PRs, ADRs, `docs/agents-map.json`). **It is deliberately not saved to a file**: a committed summary ages as soon as nobody regenerates it and ends up saying something false with an official look.

When answering:
- Show the output and, if the user wants more, go deeper with the sources it cites (`architecture.md`, the epic, the ADR).
- If something looks odd (an old open PR, an unassigned critical issue, a release open for weeks), mention it in one line.

## What can be done now

For "what can I do now?", "what's next?", "what is blocked?":

```bash
.claude/skills/project-status/available.sh
```

It returns four lists: **can be started now** (no open blockers and unassigned, by priority), **in progress** (assigned or with an open PR that closes them, with who and which PR), **blocked** (with what blocks them) and **epics in progress** (with sub-issue progress). Epics do not show up as available: they are worked through their sub-issues. Taken ones do not either: `/implement-issue` assigns the issue when it takes it, and an open PR that closes it (through `Closes #n` in the body or the number in the branch) counts too. That way two sessions do not pick the same one.

When answering:
- Show the output as is, without inventing issues that are not there.
- If the user says which area or priority they want to work on, filter the list with that.
- If there are available ones with `status:triage`, mention it: they have no priority yet.
- GitHub takes a few seconds to update the dependency summary: if an issue was just closed, it may still show for a few more seconds.

It changes nothing, so no confirmation is needed.

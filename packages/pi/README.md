# barrilete-pi

Barrilete Kit for [pi](https://github.com/badlogic/pi-mono): the same flow as in Claude Code (plan, implement, review, with the human knots), without depending on Claude Code. It does not copy the kit: it reuses the project's `.claude/skills/` and `scripts/agents/`, so a project works the same in either harness.

## What it brings

| Kit piece | In pi |
|---|---|
| Skills (`.claude/skills/`) | Added to pi's discovery: they appear in the system prompt and as `/skill:<name>`. |
| `/plan-feature`, `/implement-issue <n>`, `/review-pr <n>`, `/project-status`, `/improve-skills`, `/add-member`, `/remove-member` | Commands with the same name. Each one loads the whole `SKILL.md` into the message. |
| Guardrails (`scripts/agents/guardrails.py`) | Every bash command of the agent goes through the same script before it runs; if it blocks, pi does not run it and the agent reads why. |
| Flow line (`scripts/agents/flow.py`) | In pi's footer, refreshed when the session starts and when the agent finishes. |

Everything turns on only inside a Barrilete project (a git repo with `scripts/agents/guardrails.py`); in any other folder the package does nothing.

Not yet: `/orchestrate` and the subagents (pi has no subagents of its own; they are the next phase), so the `orchestrate` skill stays out of discovery.

## Install

Requires pi, `python3` and, for the flow line, `gh`. From a clone of the kit:

```bash
pi install ./packages/pi        # all your projects (~/.pi/agent/settings.json)
pi install -l ./packages/pi     # only this project (.pi/settings.json)
pi -e ./packages/pi             # try it in one session without installing
```

Then open pi at the project root and type `/plan-feature <idea>`.

## How it works

- `extensions/skills.ts`: `resources_discover` returns the project's skill folders, and each command builds the same `<skill>` block pi builds for `/skill:<name>`.
- `extensions/guardrails.ts`: on `tool_call` for `bash`, it sends `guardrails.py` the Claude Code hook JSON and blocks on exit 2. Like the other hooks it fails open: it is a guardrail, the lock is branch protection.
- `extensions/flow.ts`: `flow.py --format plain` in `ctx.ui.setStatus`.

If the guardrails stop a command the person did ask for, they run it themselves in pi with `!<command>`: the user's own shell commands do not go through the agent's guardrails.

## Tests

```bash
node --test packages/pi/test/*.test.ts
```

They run the extensions with a fake `pi` against this repo's real scripts and skills (Node 23.6 or newer, which runs TypeScript as is).

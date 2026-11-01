# barrilete-pi

Barrilete Kit for [pi](https://github.com/badlogic/pi-mono): the same flow as in Claude Code (plan, implement, review, with the human knots), without depending on Claude Code. It does not copy the kit: it reuses the project's `.claude/skills/` and `scripts/agents/`, so a project works the same in either harness.

## What it brings

| Kit piece | In pi |
|---|---|
| Skills (`.claude/skills/`) | Added to pi's discovery: they appear in the system prompt and as `/skill:<name>`. |
| `/plan-feature`, `/implement-issue <n>`, `/review-pr <n>`, `/orchestrate`, `/project-status`, `/improve-skills`, `/add-member`, `/remove-member` | Commands with the same name. Each one loads the whole `SKILL.md` into the message. |
| Subagents (`.claude/agents/`) for `/orchestrate` | The `subagent` tool runs `implementer`, `implementer-light` and `reviewer` as separate pi processes, each in its worktree, and returns their contract block. |
| Guardrails (`scripts/agents/guardrails.py`) | Every bash command of the agent goes through the same script before it runs; if it blocks, pi does not run it and the agent reads why. |
| Flow line (`scripts/agents/flow.py`) | In pi's footer, refreshed when the session starts and when the agent finishes. |

Everything turns on only inside a Barrilete project (a git repo with `scripts/agents/guardrails.py`); in any other folder the package does nothing.

Not yet: a `barrilete` launcher with its own home, the SketchyBar integration and publishing on npm.

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
- `extensions/subagents.ts` and `lib/subagents.ts`: the `subagent` tool. It reads the role from `.claude/agents/<role>.md` (the same definition Claude Code runs) and launches `pi --mode json -p` in the worktree with the role's model and tools, translated (`Read` → `read`, `Glob` → `find`, `ls`; `Skill` has no equivalent), plus notes on what changes in pi (no `/code-review`, so it declares `no code-review`).

## Subagents

What the contract (`docs/agents/subagent-contract.md`) requires holds in pi:

- **Guardrails always on.** The child loads only this package (`--no-extensions -e <package>`), and its guardrails use `guardrails.py` from the orchestrator's checkout, never the worktree's copy, which is the PR's unreviewed code.
- **They cannot launch other subagents.** Inside a subagent the tool is not registered.
- **Never more than 3 implementing at once.** The tool refuses the call that would go over, counting the ones already running.

The roles' models are aliases (`opus`, `sonnet`, `haiku`). pi resolves them as patterns among your models: with Anthropic, the latest of each family. For another provider, map them:

```bash
export BARRILETE_MODELS="opus=openai/gpt-5,sonnet=openai/gpt-5-mini,haiku=openai/gpt-5-nano"
```

Because the child runs with `--no-extensions`, a provider that comes from an extension of yours is not available to the subagents: map the roles to built-in providers.

If the guardrails stop a command the person did ask for, they run it themselves in pi with `!<command>`: the user's own shell commands do not go through the agent's guardrails.

## Tests

```bash
node --test packages/pi/test/*.test.ts
```

They run the extensions with a fake `pi` against this repo's real scripts, skills and agent definitions; the subagents run `test/fake-pi.mjs` in place of the child pi (Node 23.6 or newer, which runs TypeScript as is).

# barrilete-pi

Barrilete Kit for [pi](https://github.com/badlogic/pi-mono): the same flow as in Claude Code (plan, implement, review, with the human knots), without depending on Claude Code. It does not copy the kit: it reuses the project's `.claude/skills/`, `.claude/agents/` and `scripts/agents/`, so a project works the same in either harness.

## What it brings

| Kit piece | In pi |
|---|---|
| Skills (`.claude/skills/`) | Added to pi's discovery: they appear in the system prompt and as `/skill:<name>`. |
| `/plan-feature`, `/implement-issue <n>`, `/review-pr <n>`, `/orchestrate`, `/project-status`, `/improve-skills`, `/add-member`, `/remove-member` | Commands with the same name. Each one loads the whole `SKILL.md` into the message. |
| Subagents (`.claude/agents/`) for `/orchestrate` | The `subagent` tool runs `implementer`, `implementer-light` and `reviewer` as separate pi processes, each in its worktree, and returns their contract block. |
| Guardrails (`scripts/agents/guardrails.py`) | Every bash command of the agent goes through the same script before it runs; if it blocks, pi does not run it and the agent reads why. |
| Flow line (`scripts/agents/flow.py`) | In pi's footer, refreshed when the session starts and when the agent finishes. |
| Agent status | With `BARRILETE_STATUS_HOOK`, each session reports its state to a command of yours (a status bar, a notifier) in the JSON of Claude Code's hooks. |

Everything turns on only inside a Barrilete project (a git repo with `scripts/agents/guardrails.py`); in any other folder the package does nothing.

## Install

Requires `python3` and, for the skills and the flow line, `gh`. With the `barrilete` command (pi comes along if you do not have it):

```bash
npm i -g barrilete-pi
barrilete doctor                 # checks pi, python3, gh, the project and the login
barrilete home import-pi         # optional: reuse your pi login in barrilete's own home
```

Or as a package of your pi, or from a clone of the kit:

```bash
pi install npm:barrilete-pi      # all your projects (~/.pi/agent/settings.json)
pi install -l npm:barrilete-pi   # only this project (.pi/settings.json)
pi -e ./packages/pi              # from a clone, one session without installing
```

Then open it at the project root and type `/plan-feature <idea>`.

## The barrilete command

`barrilete` opens pi with this package loaded, without installing it into your pi or editing its settings. By default it uses its own home, `~/.barrilete/agent` (`BARRILETE_HOME` moves it): its login, settings and sessions never touch your pi installation. The rest of the options go to pi as they are.

| Command | What it does |
|---|---|
| `barrilete [pi options]` | pi with barrilete-pi, in its own home. |
| `barrilete --link [pi options]` | The same, in your pi home (`~/.pi/agent`, or `PI_CODING_AGENT_DIR`): your login, models and sessions. |
| `barrilete home import-pi [--dry-run]` | Copies your pi login (`auth.json`, `0600`) and default model into the own home. It never overwrites, and it copies no packages, extensions or sessions. |
| `barrilete doctor` | Checks pi, `python3`, `gh`, the project, the login and the status hook. |

With `import-pi` there are two copies of the login: a provider that rotates refresh tokens can log one of them out. `--link` shares a single one.

It uses the `pi` on your PATH; without one, the one npm installed with the package.

## Agent status

Set `BARRILETE_STATUS_HOOK` to a command and every pi session reports to it, on stdin, the same JSON Claude Code's hooks send (`session_id`, `hook_event_name`, `cwd`, `tool_name`): a script written for Claude Code's hooks works as is.

| pi | Event |
|---|---|
| The session starts / ends | `SessionStart` / `SessionEnd` |
| A prompt arrives | `UserPromptSubmit` |
| A tool runs | `PreToolUse`, then `PostToolUse` (`PostToolUseFailure` if it failed) |
| The `subagent` tool | `SubagentStart` and `SubagentStop`, one per subagent |
| The agent finishes | `Stop` (`StopFailure` if the model ended in error) |

The calls go in order, one after the other, so a late event never overwrites the final state. A subagent does not report itself: its orchestrator counts it. For example, to see pi's agents in a SketchyBar that already listens to Claude Code:

```bash
export BARRILETE_STATUS_HOOK="$HOME/.config/sketchybar/plugins/agent_hook.sh"
```

## How it works

- `extensions/skills.ts`: `resources_discover` returns the project's skill folders, and each command builds the same `<skill>` block pi builds for `/skill:<name>`.
- `extensions/guardrails.ts`: on `tool_call` for `bash`, it sends `guardrails.py` the Claude Code hook JSON and blocks on exit 2. Like the other hooks it fails open: it is a guardrail, the lock is branch protection.
- `extensions/flow.ts`: `flow.py --format plain` in `ctx.ui.setStatus`.
- `extensions/subagents.ts` and `lib/subagents.ts`: the `subagent` tool. It reads the role from `.claude/agents/<role>.md` (the same definition Claude Code runs) and launches `pi --mode json -p` in the worktree with the role's model and tools, translated (`Read` → `read`, `Glob` → `find`, `ls`; `Skill` has no equivalent), plus notes on what changes in pi (no `/code-review`, so it declares `no code-review`).
- `extensions/status.ts` and `lib/status.ts`: the agent status.
- `bin/barrilete.mjs`: the command.

If the guardrails stop a command the person did ask for, they run it themselves in pi with `!<command>`: the user's own shell commands do not go through the agent's guardrails.

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

## Tests

```bash
node --test packages/pi/test/*.test.ts
```

They run the extensions with a fake `pi` against this repo's real scripts, skills and agent definitions; the subagents run `test/fake-pi.mjs` in place of the child pi, and the command a fake `pi` on the PATH with `HOME` in a temp dir (Node 23.6 or newer, which runs TypeScript as is).

## Publish

A person publishes, after the merge, from `packages/pi` on the base branch: bump `version` in `package.json`, check the contents with `npm pack --dry-run` and run `npm publish`. The package is unscoped and public.

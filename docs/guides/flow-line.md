# Flow line in the terminal

> `scripts/agents/flow.py` prints, in one line, which step of the flow the current branch is in. It does not depend on the agent: any harness or ADE that can show a line of text can show it.

```
plan ● ─ implement ─ ▸review ─ ● merge   #176 · PR #179 in review
```

The two ● are the knots that stay in human hands: approving the plan and merging. The step comes from what already exists, nobody writes it by hand:

| What there is | Step |
|---|---|
| A branch `<type>/<n>-…` (also `claude/<n>-…`) with no open PR, or with a draft PR | implement |
| An open PR for the branch | review |
| The PR approved (the required review or, if the repo requires none, an approval and no change requests) | ● merge (waiting for your merge) |
| The PR merged | retro |
| The issue with `status:blocked` | ✖ blocked, whatever the step |
| A trunk branch or one without an issue number | no step marked |

`/plan-feature` leaves no trace in git, so the plan knot is never the current step. What it asks GitHub (`gh`) is cached per branch for 30 seconds in the git dir. Once that time is up, the line keeps showing what it had while a background process refreshes it, so the prompt does not wait for the network; only the first prompt on a branch it has never seen waits for `gh` (up to 4 seconds without network). A call that fails keeps what the cache had: a timeout on the PR does not turn into "no PR yet", and one on the issue does not hide a `status:blocked`. Without `gh` or without network, it shows what git knows.

## Where to show it

| Where | How | What it uses |
|---|---|---|
| Claude Code | native status line | `--statusline` |
| GitHub Copilot CLI | its status line (experimental, behind a feature flag: check its docs) | `--statusline` |
| Codex CLI, or any agent in a terminal | tmux bar or the shell prompt | `--format tmux` / `zsh` / `bash` |
| Cursor, VS Code, Windsurf, any ADE | a terminal pane that redraws itself | `--watch` |
| An extension or a dashboard | it draws the line its own way | `--format json` |

Codex CLI's status line only takes its built-in items, not a command, so tmux or the prompt is the way there.

### Claude Code

`init-template.sh` asks whether to turn it on when it runs in a terminal; `--flow-line` or `--no-flow-line` answer in advance. The choice is recorded as `flow_line` in `.agent-kit.json`, and `update.py` and `grow.py` keep it. To turn it on later, by hand, in `.claude/settings.json` (shared) or `.claude/settings.local.json` (only you; if you merge it into an existing `hooks`, keep the guardrails one):

```json
{
  "statusLine": {
    "type": "command",
    "command": "f=\"$(git rev-parse --show-toplevel 2>/dev/null)/scripts/agents/flow.py\"; [ -f \"$f\" ] || exit 0; exec python3 \"$f\" --statusline",
    "refreshInterval": 1
  },
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "f=\"$(git rev-parse --show-toplevel 2>/dev/null)/scripts/agents/flow.py\"; [ -f \"$f\" ] || exit 0; exec python3 \"$f\" --busy on"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "f=\"$(git rev-parse --show-toplevel 2>/dev/null)/scripts/agents/flow.py\"; [ -f \"$f\" ] || exit 0; exec python3 \"$f\" --busy off"}]}]
  }
}
```

**While the agent works, the line moves.** The two hooks mark the turn: `UserPromptSubmit` turns the mark on with the time it started and `Stop` turns it off (one mark per session, in the system temp dir; a mark older than 6 hours is ignored, in case a session died without `Stop`). `refreshInterval: 1` makes Claude Code run the command every second (it needs Claude Code 2.1.97 or newer; an older one ignores it and only refreshes on each message), so meanwhile the line shows a spinner and the elapsed time, and in the template the face looks around:

```
( ●●) plan ● ─ ▸implement ─ review ─ ● merge   #42 · no PR yet   ⠹ working 1m 12s
```

The other harnesses have no equivalent hooks, so there the line does not move.

### Shell prompt

```zsh
# ~/.zshrc
setopt prompt_subst
RPROMPT='$(f="$(git rev-parse --show-toplevel 2>/dev/null)/scripts/agents/flow.py"; [ -f "$f" ] && python3 "$f" --format zsh)'
```

```bash
# ~/.bashrc
flow_line() { local f; f="$(git rev-parse --show-toplevel 2>/dev/null)/scripts/agents/flow.py"; [ -f "$f" ] && python3 "$f" --format bash; }
PS1='$(flow_line)\n\w \$ '
```

The `zsh` and `bash` formats wrap the colors so the shell does not count them as width and the cursor does not drift.

### tmux

tmux ends `#(…)` at the first `)`, so the path goes between backticks and not in `$(…)`.

```tmux
# ~/.tmux.conf
set -g status-interval 5
set -g status-right-length 120
set -g status-right '#(cd "#{pane_current_path}" && f="`git rev-parse --show-toplevel 2>/dev/null`/scripts/agents/flow.py" && [ -f "$f" ] && python3 "$f" --format tmux)'
```

### A pane in any ADE

```bash
python3 scripts/agents/flow.py --watch      # redraws every 5 s; --watch 2 for every 2 s
```

### JSON

```bash
python3 scripts/agents/flow.py --format json
# {"brand": false, "branch": "claude/176-…", "issue": 176, "pr": 179, "step": "review", "note": null, "face": "working", "steps": [...], "text": "…"}
```

`step` is `implement`, `review`, `merge`, `retro`, `blocked` or `null`; `note` qualifies an `implement`: `draft`, `closed` (PR closed without merge) or `offline` (gh did not answer). Outside a git repo it prints `null`.

## Colors

Shades of the kit's palette that read on a dark and on a light terminal (contrast of at least 3:1 on both; the brand's amber and blue do not read on white, nor its grey on black): amber for the knots, blue for the current step, grey for the rest and red for blocked. `NO_COLOR=1` or `--format plain` turns them off. The rest is the brand's: see [Barrilete's faces](#barriletes-faces).

## Barrilete's faces

In the template repo (with `.github/brand/`) the line starts with Barrilete's face for the step, the states of `.github/brand/states/`, and `--watch` draws it big beside what it means. `init-template.sh` deletes that folder, so a project shows the line without faces, like the rest of the brand.

| Face | State | Step |
|---|---|---|
| `(● ●)` | working | implement, review, retro |
| `(• • •)` | planning | no step (trunk branch) |
| `(✕ ✕)` | blocked | blocked |
| `(^ ^)` | PR ready, amber mouth | ● merge |

```
━━━┳━━     ━━┳━━━
 ╭─┸─────────┸─╮
 │ ┌─────────┐ │
 │ │  ^   ^  │ │   PR ready
 │ └─────────┘ │   claude/42-validate-qr
 ╰─────▆▆▆─────╯

plan ● ─ implement ─ review ─ ▸● merge   #42 · PR #50 waiting for your merge
```

`flow.py --face working|planning|blocked|ready` prints the big face on its own; the init uses it to say goodbye. The JSON brings `face` so an extension can draw it its own way.

## Tests

`python3 -m unittest scripts/agents/test_flow.py` (it runs with `verify.py` when `flow.py` changes). The end-to-end cases use a real git repo and a fake `gh` on the `PATH`.

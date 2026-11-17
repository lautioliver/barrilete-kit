# Agent log (`bitacora.py`)

`scripts/agents/bitacora.py` builds one page with what each agent did in each change: a card per PR with every agent that touched it (role and model) and what it reported in its retro (#339). It reads the retros that `retro.sh` saves on the `agents/retros` branch and the PRs of `gh pr list`, and writes `.barrilete/bitacora.html` (ignored by git, one self-contained file).

```bash
python3 scripts/agents/bitacora.py                      # this repo, barrilete design (+ the project's, if any)
python3 scripts/agents/bitacora.py -C ../other-repo     # another repo
python3 scripts/agents/bitacora.py --theme barrilete    # ignore .barrilete/bitacora.css
python3 scripts/agents/bitacora.py --theme design.css   # use that file instead of .barrilete/bitacora.css
```

The labels follow `language` in `.agent-kit.json` (`en` or `es`; without it, `en`). It prints `ok: <path>` and ends with 0. A usage error (a `--theme` file that does not exist, an unknown option) is one line and 64. If `gh` fails (no session, no network) the page is still written, without PR titles or states. Without retros, the page says so. Running it twice with the same retros gives the same page.

It is not installed in `--small` mode, which has no retros (`.claude/skills/improve-skills` is not installed there).

## The retro contract

The log depends on what `retro.sh` writes (`.claude/skills/improve-skills/retro.sh`, template in `retro-template.md`). If one of these changes, change `bitacora.py` in the same PR; `scripts/agents/test-bitacora.sh` writes a retro with `retro.sh` and fails if the log stops reading it.

- **Where:** `retros/*.md` on the `agents/retros` branch and on the 0.9 one, `agentes/retros` (if a file is on both, the new one wins). The one on `origin` if the repo has that remote (it fetches it first); otherwise the local one. It reads them with `retros_dump` of `.claude/skills/improve-skills/legacy-names.sh`, the same table `retro.sh` and `/improve-skills` use: 0.9 keys and values (`rol: revisor`, `modelo:`, `fecha:`) are read as the new ones, quotes around a value are dropped and, if a key repeats, the first one wins.
- **Frontmatter** (between two `---` lines), `key: value` lines:
  - `pr`: number of the PR (with or without `#`). The retros are grouped by PR.
  - `issue`: number of the issue. Without a PR, the retros are grouped by issue; without either, each retro is its own card.
  - `role`: `implementer`, `implementer-light`, `reviewer`, `orchestrator` or `session` (`retro.sh` writes `session` if it is missing).
  - `model`: `opus`, `sonnet`, `haiku` or `unknown`.
  - `skill`: `implement-issue`, `review-pr`, `orchestrate` or `improve-skills` (what the agent did).
  - `date`: `YYYY-MM-DD` (`retro.sh` fills it in). The most recent changes go first.
- **Body:** sections that start a line with `**Title:**`. The four of the template (`Deviations`, `Decisions not covered`, `What the review found`, `Proposal`, or their Spanish forms) are translated to the language of the page; any other title is shown as written. A body without sections is shown whole as the report.

Everything in a retro is text: it is escaped, never interpreted as HTML.

## The design: tokens

The page uses only these tokens. The barrilete design (`scripts/agents/bitacora/barrilete.css`) gives them their default values, for light and dark mode (it follows the system with `prefers-color-scheme`).

| Token | What it is | Light | Dark |
|---|---|---|---|
| `--bg` | page background | `#F6F7F9` | `#121418` |
| `--surface` | blocks inside a card, code | `#E9ECF1` | `#1C1F26` |
| `--card` | cards | `#FFFFFF` | `#23262E` |
| `--ink` | text | `#14161A` | `#ECEEF2` |
| `--muted` | secondary text | `#5A6270` | `#A3AAB6` |
| `--accent` | links and agent labels | `#2450E0` | `#8FB0FF` |
| `--ok` | merged | `#17693D` | `#5FD39A` |
| `--warn` | open | `#8A5300` | `#FFB020` |
| `--danger` | closed | `#B4122B` | `#FF8A96` |
| `--font-display` | titles | Bricolage Grotesque, then the system's | |
| `--font-mono` | everything else | JetBrains Mono, then the system's | |

Every text color reaches WCAG AA (4.5:1) on `--bg`, `--surface` and `--card` in both modes; the test checks it. Two light values differ from the barrilete status page because they did not reach it as text: `--accent` (`#2B59FF` gave 4.46 on `--surface`) and `--warn` (`#FFB020` gave 1.7; it stays as the dark one).

The fonts come from Google Fonts with `display=swap`: without network, the text is shown at once with the system fonts.

### The project's design

If the project has `.barrilete/bitacora.css`, it goes after the barrilete design and overrides the tokens it defines; whatever it does not define stays as barrilete. It is the project's file: the kit does not install it, and it is versioned like any other.

```css
/* .barrilete/bitacora.css */
:root {
  --accent: #0E9F6E;
  --font-display: "Inter", system-ui, sans-serif;
}
@media (prefers-color-scheme: dark) {
  :root { --accent: #6EE7B7; }
}
```

A token defined only in `:root` applies to both modes (a later `:root` wins over barrilete's dark block): to give dark mode its own value, define it in the `@media` block too, as in the example. If you change colors, check the contrast yourself: the test only checks barrilete's.

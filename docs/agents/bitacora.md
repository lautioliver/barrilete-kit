# Project log (`/bitacora`)

`docs/bitacora.html` is the project log: one file per project, versioned in git so every member has it, with one section per topic (#343). A person adds an entry from the chat with `/bitacora <topic>` (skill `.claude/skills/bitacora/`): the agent writes it with the context of that conversation (what changed and why, what was decided, how it was checked, what is still open) and `scripts/agents/bitacora_add.py` inserts it. Nothing generates entries on its own.

```bash
python3 scripts/agents/bitacora_add.py find --topic "Decide the route"
python3 scripts/agents/bitacora_add.py add --topic "Decide the route" --entry /tmp/entry.html
python3 scripts/agents/bitacora_add.py add --topic "Decide the routes" --into decide-the-route --entry /tmp/entry.html
python3 scripts/agents/bitacora_add.py -C ../other-repo add --topic "Release" --new --entry /tmp/entry.html
```

## How entries are added

- **The section is the topic.** Its slug (lowercase, no accents, hyphens) is its id and its link: `docs/bitacora.html#decide-the-route`. Two topics with the same slug are the same section.
- **Only inserts.** A new section goes at the end of `<main>` and its link at the end of the index; an entry goes at the end of its section, with the date (`--date YYYY-MM-DD`, today by default). Everything that was there stays byte for byte; the test checks it with a diff that only allows inserted lines. The places to insert are HTML comments (`<!-- bitacora:nav -->`, `<!-- bitacora:main -->`, `<!-- bitacora:end <slug> -->`): if the file lost them (edited by hand), the script does not touch it and exits with 65.
- **A similar name is asked about.** `find` answers `exact <slug>`, `none <slug>` (exit 0) or one `similar <slug>\t<topic>` line per similar section (exit 3): a slug that contains the other one between hyphens, or a `difflib` ratio of 0.8 or more. `add` with a similar section and without `--into <slug>` or `--new` writes nothing and exits with 3; the skill asks the person and repeats with their answer.
- **The entry is an HTML fragment** that uses the components below, checked against an allowlist (attribute values after their entities are decoded; exit 64 otherwise, the file is not touched). Tags: text and lists (`p`, `br`, `hr`, `strong`, `b`, `em`, `i`, `u`, `s`, `small`, `mark`, `code`, `pre`, `kbd`, `sub`, `sup`, `span`, `div`, `h3`, `h4`, `ul`, `ol`, `li`, `dl`, `dt`, `dd`, `blockquote`, `abbr`, `time`), links (`a`) and tables (`table`, `caption`, `thead`, `tbody`, `tfoot`, `tr`, `th`, `td`). Attributes: `class` and `title` on any of them, `href` on `a` (relative, `#`, `http(s)` or `mailto` only), `datetime` on `time`, `colspan`, `rowspan` and `scope` on cells, and `style` only on `i` and only as the width of a bar (`--v:70%`). On top of that, no tag can carry `on…=` or `javascript:` in its raw text (the text between tags can name them), the entry cannot have comments, CDATA or a loose `<` (write `&lt;`, which passes), and every tag it opens has to be closed with its closing tag: `<b/>` does not close it (only `<br/>` and `<hr/>` can be written that way). The topic is always written escaped, as text, and it cannot take an id the page already uses (`theme-…`, `structure`).
- **CRLF and mode.** A file with CRLF line endings (a Windows checkout) is read the same and the inserts keep its line endings. Writing keeps the file's mode (a new file gets the one the umask gives).
- **The file is created** the first time, with the labels in the language of `language` in `.agent-kit.json` (`en` or `es`; without it, `en`) and the design of that moment. Other exits: 64 for a usage error (also outside a git repo), 1 if it cannot read or write.

The page has no scripts. The kit does not ship a `docs/bitacora.html`: each project creates its own with its first `/bitacora`.

## Components

The page carries the styles of these classes; the skill lists their HTML.

| Class | What for |
|---|---|
| `kpis` + `kpi` | key numbers, with `ok`, `warn` or `danger` |
| `cards` + `card` | cards by status (done, in progress, waiting on you) |
| `tbl` | tables: before/after, options; they scroll sideways on a phone |
| `bars` + `bar` | bars, with the width in `style="--v:70%"` |
| `flow` | a flow of steps (`<ol>`) |
| `note` | a highlighted note |
| `ok`, `warn`, `danger` | status: done, in progress, waiting on a person or broken |

## The design: tokens

The page has the shape of the barrilete status HTML: on top the project name with the drone and the leash, the contents in a fixed dark bar, each topic as a numbered section (`>_ 01`) and its entries on the leash, one below the other, with their date. The brand colors of the drone, the bar and the footer are fixed; everything else uses only these tokens. The barrilete design (`scripts/agents/bitacora/barrilete.css`) gives them their default values, for light and dark mode (it follows the system with `prefers-color-scheme`).

| Token | What it is | Light | Dark |
|---|---|---|---|
| `--bg` | page background | `#F6F7F9` | `#121418` |
| `--surface` | blocks inside an entry, code | `#E9ECF1` | `#1C1F26` |
| `--card` | entries | `#FFFFFF` | `#23262E` |
| `--ink` | text | `#14161A` | `#ECEEF2` |
| `--muted` | secondary text | `#5A6270` | `#A3AAB6` |
| `--accent` | links and highlights | `#2450E0` | `#8FB0FF` |
| `--ok` | done | `#17693D` | `#5FD39A` |
| `--warn` | in progress | `#8A5300` | `#FFB020` |
| `--danger` | waiting on you, broken | `#B4122B` | `#FF8A96` |
| `--knot` | fill of the leash knots, in-progress bars and notes; never text | `#FFB020` | `#FFB020` |
| `--font-display` | titles | Bricolage Grotesque, then the system's | |
| `--font-mono` | everything else | JetBrains Mono, then the system's | |

Every text color reaches WCAG AA (4.5:1) on `--bg`, `--surface` and `--card` in both modes; the test checks it. Two light values differ from the barrilete status page because they did not reach it as text: `--accent` (`#2B59FF` gave 4.46 on `--surface`) and `--warn` (`#FFB020` gave 1.7; it stays as the dark one).

The fonts come from Google Fonts with `display=swap`: without network, the text is shown at once with the system fonts.

### The project's design

If the project has `.barrilete/bitacora.css`, it goes after the barrilete design (both are copied into the page when it is created) and overrides the tokens it defines; whatever it does not define stays as barrilete. It is the project's file: the kit does not install it, and it is versioned like any other.

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

The design is copied into the page when it is created, and entries never rewrite it: a page that already exists keeps the design it was born with. To give it a new one, change the `<style id="theme-…">` blocks by hand in a PR of its own.

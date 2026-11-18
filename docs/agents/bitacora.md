# Project log (`/bitacora`)

`docs/bitacora.html` is the project log: one file per project, versioned in git so every member has it, with one section per topic (#343). A person adds an entry from the chat with `/bitacora <topic>` (skill `.claude/skills/bitacora/`): the agent writes it with the context of that conversation (the idea, its options, what was dropped and why, what was decided, what is missing) and `scripts/agents/bitacora_add.py` inserts it. Nothing generates entries on its own.

```bash
python3 scripts/agents/bitacora_add.py find --topic "Decide the route"
python3 scripts/agents/bitacora_add.py add --topic "Decide the route" --entry /tmp/entry.html
python3 scripts/agents/bitacora_add.py add --topic "Decide the routes" --into decide-the-route --entry /tmp/entry.html
python3 scripts/agents/bitacora_add.py -C ../other-repo add --topic "Release" --new --entry /tmp/entry.html
```

## What it is for

The log is where the project's **ideas are thought through** with the context of the chat, and where it stays how each one was reached. A person asks for `/bitacora <topic>` while talking an idea through and the agent draws it in that topic's section: how it works, which options there were, what was dropped and why, what was decided and what is missing. It is written with drawings, little text and plain words, with no file names or code jargon (#361).

| | Log | Retros | PRs |
|---|---|---|---|
| For whom | the people on the team | the agents and `/improve-skills` | whoever reviews the change |
| What it tells | the idea, its options and why it was decided | what went well or wrong while working | what was touched and how it was checked |
| How it speaks | drawings and plain words | technical | technical |

## How entries are added

- **The section is the topic.** Its slug (lowercase, no accents, hyphens) is its id and its link: `docs/bitacora.html#decide-the-route`. Two topics with the same slug are the same section.
- **Only inserts.** A new section goes at the end of `<main>` and its link at the end of the index; an entry goes at the end of its section, with the date (`--date YYYY-MM-DD`, today by default). Everything that was there stays byte for byte; the test checks it with a diff that only allows inserted lines. The places to insert are HTML comments (`<!-- bitacora:nav -->`, `<!-- bitacora:main -->`, `<!-- bitacora:end <slug> -->`): if the file lost them (edited by hand), the script does not touch it and exits with 65.
- **A similar name is asked about.** `find` answers `exact <slug>`, `none <slug>` (exit 0) or one `similar <slug>\t<topic>` line per similar section (exit 3): a slug that contains the other one between hyphens, or a `difflib` ratio of 0.8 or more. `add` with a similar section and without `--into <slug>` or `--new` writes nothing and exits with 3; the skill asks the person and repeats with their answer.
- **The entry is an HTML fragment** that uses the components below, checked against an allowlist (attribute values after their entities are decoded; exit 64 otherwise, the file is not touched). Tags: text and lists (`p`, `br`, `hr`, `strong`, `b`, `em`, `i`, `u`, `s`, `small`, `mark`, `code`, `pre`, `kbd`, `sub`, `sup`, `span`, `div`, `h3`, `h4`, `ul`, `ol`, `li`, `dl`, `dt`, `dd`, `blockquote`, `abbr`, `time`), links (`a`) and tables (`table`, `caption`, `thead`, `tbody`, `tfoot`, `tr`, `th`, `td`). Attributes: `class` and `title` on any of them, `href` on `a` (relative, `#`, `http(s)` or `mailto` only; `//host` and `\\host` are another site and do not pass), `datetime` on `time`, `colspan`, `rowspan` and `scope` on cells, and `style` only on `i` and only as the width of a bar (`--v:70%`). So an `on…=` handler does not pass because it is not among the attributes, and neither does `javascript:`, because it is not an allowed scheme in `href`; the text and attribute values can name them (`?only=open` in a link passes). On top of that, the entry cannot have comments, CDATA or a loose `<` (write `&lt;`, which passes), and every tag it opens has to be closed with its closing tag: `<b/>` does not close it (only `<br/>` and `<hr/>` can be written that way; `</br>` does not close anything and does not pass), and the entry cannot end in a tag left half written (`<b`, `<a href="x`). The topic is always written escaped, as text, and it cannot take an id the page already uses (`theme-…`, `structure`).
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
| `branch` + `root`, `opts`, `opt` | branch diagram: a question and its options (`opt` with `ok` chosen or `danger` dropped) |
| `map` + `node`, `edge` | map of parts: one row per connection, "part → what it does → part" |
| `ok`, `warn`, `danger` | status: done, in progress, waiting on a person or broken |

## The design: tokens

The page has the shape of the barrilete status HTML: on top the project name with the drone and the leash, the contents in a fixed light bar, each topic as a numbered section (`>_ 01`) and its entries on the leash, one below the other, with their date. The brand colors of the drone are fixed; everything else uses only these tokens. The barrilete design (`scripts/agents/bitacora/barrilete.css`) gives them their default values. The page is **always light**: it does not follow the system's dark mode (`color-scheme: light`; the person decided it in #361, before it followed the system).

| Token | What it is | Value |
|---|---|---|
| `--bg` | page background | `#F6F7F9` |
| `--surface` | blocks inside an entry, code | `#E9ECF1` |
| `--card` | entries | `#FFFFFF` |
| `--ink` | text | `#14161A` |
| `--muted` | secondary text | `#5A6270` |
| `--accent` | links and highlights | `#2450E0` |
| `--ok` | done | `#17693D` |
| `--warn` | in progress | `#8A5300` |
| `--danger` | waiting on you, broken | `#B4122B` |
| `--knot` | fill of the leash knots, in-progress bars and notes; never text | `#FFB020` |
| `--font-display` | titles | Bricolage Grotesque, then the system's |
| `--font-mono` | everything else | JetBrains Mono, then the system's |

Every text color reaches WCAG AA (4.5:1) on `--bg`, `--surface` and `--card`; the test checks it. Two values differ from the barrilete status page because they did not reach it as text: `--accent` (`#2B59FF` gave 4.46 on `--surface`) and `--warn` (`#FFB020` gave 1.7; it is `#8A5300`).

The fonts come from Google Fonts with `display=swap`: without network, the text is shown at once with the system fonts.

### The project's design

If the project has `.barrilete/bitacora.css`, it goes after the barrilete design (both are copied into the page when it is created) and overrides the tokens it defines; whatever it does not define stays as barrilete. It is the project's file: the kit does not install it, and it is versioned like any other.

```css
/* .barrilete/bitacora.css */
:root {
  --accent: #0E9F6E;
  --font-display: "Inter", system-ui, sans-serif;
}
```

The page is always light: do not add a `@media (prefers-color-scheme: dark)` block (if you have one from the earlier example, remove it), because it would bring dark colors back onto a light background. If you change colors, check the contrast yourself: the test only checks barrilete's.

The design is copied into the page when it is created, and entries never rewrite it: a page that already exists keeps the design it was born with. To give it a new one, change the `<style id="theme-…">` blocks by hand in a PR of its own.

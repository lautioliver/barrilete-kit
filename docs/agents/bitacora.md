# Project log (`/bitacora`)

The project log is versioned in git so every member has it (#343) and is split by month (#365): `docs/bitacora.html` is the **front page** (the index of months and one section per topic, with a link to each month where the topic has entries) and the entries live in the page of their month, `docs/bitacora/YYYY-MM.html`, with one section per topic. A person adds an entry from the chat with `/bitacora <topic>` (skill `.claude/skills/bitacora/`): the agent writes it with the context of that conversation (the idea, its options, what was dropped and why, what was decided, what is missing) and `scripts/agents/bitacora_add.py` inserts it. Nothing generates entries on its own.

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

- **The section is the topic.** Its slug (lowercase, no accents, hyphens) is its id and its link, on the front page and in each month's page: `docs/bitacora.html#decide-the-route` (the topic and its months), `docs/bitacora/2026-11.html#decide-the-route` (its entries of that month). Two topics with the same slug are the same section. A topic that comes back in another month keeps the name it already had.
- **Only the current month is written.** The entry goes to the page of the month of its date; the pages of past months are not touched. `--date YYYY-MM-DD` (today by default) cannot be in the future nor from a month before the newest page (exit 64): it would write a past page.
- **Only inserts.** In the month's page, a new section goes at the end of `<main>` and its link at the end of the index; an entry goes at the end of its section, with the date. On the front page, a month goes at the top of the list of months and a topic at the end, with its months in `<ul class="meses">`. Everything that was there stays byte for byte; the test checks it with a diff that only allows inserted lines. The places to insert are HTML comments (`<!-- bitacora:nav -->`, `<!-- bitacora:main -->`, `<!-- bitacora:end <slug> -->`, and on the front page `<!-- bitacora:months -->`, which is what tells it from a log from before the split): if a page lost them (edited by hand), the script does not touch anything and exits with 65.
- **Order when writing:** first the log from before the split is moved (if there is one), then the front page, then the month's page. If it stops halfway, what was written is not lost and the entry is not anywhere yet: repeating the `add` finishes it, because the front page only gets what it is missing.
- **A log from before the split** (`docs/bitacora.html` with the entries inside) is moved unchanged to `docs/bitacora-anterior.html` with the first new entry, and the front page links it as «earlier», also from each of its topics. If `docs/bitacora-anterior.html` already exists, nothing is touched (exit 65). An old link `docs/bitacora.html#<topic>` lands on that topic's section of the front page, with its months.
- **If the front page is missing,** it is built again from `docs/bitacora-anterior.html` and the month pages, in that order.
- **A similar name is asked about.** `find` answers `exact <slug>`, `none <slug>` (exit 0) or one `similar <slug>\t<topic>` line per similar section (exit 3): a slug that contains the other one between hyphens, or a `difflib` ratio of 0.8 or more. `add` with a similar section and without `--into <slug>` or `--new` writes nothing and exits with 3; the skill asks the person and repeats with their answer.
- **The entry is an HTML fragment** that uses the components below, checked against an allowlist (attribute values after their entities are decoded; exit 64 otherwise, the file is not touched). Tags: text and lists (`p`, `br`, `hr`, `strong`, `b`, `em`, `i`, `u`, `s`, `small`, `mark`, `code`, `pre`, `kbd`, `sub`, `sup`, `span`, `div`, `h3`, `h4`, `ul`, `ol`, `li`, `dl`, `dt`, `dd`, `blockquote`, `abbr`, `time`), links (`a`) and tables (`table`, `caption`, `thead`, `tbody`, `tfoot`, `tr`, `th`, `td`). Attributes: `class` and `title` on any of them, `href` on `a` (relative, `#`, `http(s)` or `mailto` only; `//host` and `\\host` are another site and do not pass), `datetime` on `time`, `colspan`, `rowspan` and `scope` on cells, and `style` only on `i` and only as the width of a bar (`--v:70%`). So an `on…=` handler does not pass because it is not among the attributes, and neither does `javascript:`, because it is not an allowed scheme in `href`; the text and attribute values can name them (`?only=open` in a link passes). On top of that, the entry cannot have comments, CDATA or a loose `<` (write `&lt;`, which passes), and every tag it opens has to be closed with its closing tag: `<b/>` does not close it (only `<br/>` and `<hr/>` can be written that way; `</br>` does not close anything and does not pass), and the entry cannot end in a tag left half written (`<b`, `<a href="x`). The topic is always written escaped, as text, and it cannot take an id the page already uses (`theme-…`, `structure`).
- **CRLF and mode.** A file with CRLF line endings (a Windows checkout) is read the same and the inserts keep its line endings. Writing keeps the file's mode (a new file gets the one the umask gives).
- **The pages are created** the first time, with the labels in the language of `language` in `.agent-kit.json` (`en` or `es`; without it, `en`) and the design of that moment. Other exits: 64 for a usage error (also outside a git repo), 1 if it cannot read or write.

The pages have no scripts. The kit does not ship a `docs/bitacora.html` or a `docs/bitacora/`: each project creates its own with its first `/bitacora`. On the front page, the «started on» chip only appears in a log born with the split; a month's page carries its month in the chip and in the title, and a link back to the front page.

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

The script writes, on the front page only, `main.temas` (the topics) and `meses` (the links of a topic to its months); an entry does not use them.

## The design: tokens

The page has the shape of the barrilete status HTML: on top the project name with the drone and the leash, the contents in a fixed light bar, each topic as a numbered section (`>_ 01`) and its entries on the leash, one below the other, with their date. The brand colors of the drone, the footer and the contents highlight are fixed; everything else uses these tokens, with the values of the barrilete design (`scripts/agents/bitacora/barrilete.css`). The page is **always light**: it does not follow the system's dark mode (`color-scheme: light`; the person decided it in #361, before it followed the system).

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

### One design for every project

Every project that uses barrilete-kit has the same log: the barrilete design, always light (the person decided it in #361). A project does not change it: the script no longer reads `.barrilete/bitacora.css`, and if the file exists it does not go into the page. If your project had one, you can delete it.

The design is copied into the page when it is created, and entries never rewrite it: a page that already exists keeps the design it was born with. To give it a new one, change the `<style id="theme-…">` blocks by hand in a PR of its own.

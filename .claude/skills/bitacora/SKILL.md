---
name: bitacora
description: Saves what is being talked about in this chat as an entry of the project log (docs/bitacora.html), in the section of a topic, with numbers, tables and status colors so a person can read it at a glance. Only when the person asks, with "/bitacora <topic>", "save this in the log", "add it to the bitácora".
---

# Project log (`/bitacora <topic>`)

The project has **one** log, `docs/bitacora.html`, versioned in git so every member has it. It has one section per topic; each `/bitacora <topic>` adds an entry, with its date, **below** what the section already had. Nothing that was written is rewritten: `scripts/agents/bitacora_add.py` only inserts, and it creates the file the first time.

Run it only when the person asks for it. The entry is written from **this conversation**: what changed and why, what was decided, how it was checked and what is still open. It is for a person who was not in the chat.

## 1. Find the section

```bash
python3 scripts/agents/bitacora_add.py find --topic "<topic>"
```

- `exact <slug>` (exit 0): the section exists; the entry goes below.
- `none <slug>` (exit 0): there is no section; it is created at the end.
- `similar <slug>\t<topic>` (exit 3), one line per section with a similar name: **ask the person before writing**, naming the sections it found ("Do you mean the section «Decide the route», or is it a new one?"). Their answer decides the flag of step 3: `--into <slug>` for an existing section, `--new` for a new one. Without an answer, do not write.

If no `<topic>` was given, propose one in a few words from the conversation and confirm it before step 3.

## 2. Write the entry

A file with an HTML fragment (no `<html>`, `<head>` or `<body>`), in the language of the installation (`language` in `.agent-kit.json`; `en` without it), in plain words. Do not repeat the date or the topic: the script writes them. Keep it short: what someone needs to pick up the idea.

What goes in, in this order, leaving out what does not apply:
1. **What changed and why**, in one or two `<p>`.
2. **A number or a graph when it helps**: before/after, progress, a flow.
3. **Decisions**: the ones taken and the ones still open, with who has to decide.
4. **What is next**, with its status.

Components (the page already has their styles; they use the design tokens and work in light and dark mode):

| Component | HTML |
|---|---|
| Key numbers | `<div class="kpis"><div class="kpi ok"><b>12</b> cases pass</div><div class="kpi warn"><b>2</b> open</div></div>` |
| Cards by status | `<div class="cards"><div class="card ok"><h3>Done</h3><p>…</p></div><div class="card warn"><h3>In progress</h3><p>…</p></div><div class="card danger"><h3>Waiting on you</h3><p>…</p></div></div>` |
| Table (before/after, options) | `<table class="tbl"><tr><th>Before</th><th>After</th></tr><tr><td>…</td><td>…</td></tr></table>` |
| Bars | `<div class="bars"><div class="bar ok"><span>Done</span><i style="--v:70%"></i></div></div>` |
| Flow | `<ol class="flow"><li>issue</li><li>red</li><li>green</li><li>PR</li></ol>` |
| Note | `<div class="note warn"><p>…</p></div>` |
| Status in text | `<span class="ok">done</span>`, `<span class="warn">in progress</span>`, `<span class="danger">waiting on you</span>` |

Status colors: `ok` done, `warn` in progress, `danger` waiting on a person or broken. Never only the color: the word says it too.

Use only these components and plain text tags (`p`, `strong`, `em`, `code`, `ul`/`ol`/`li`, `a href`, `h3`…): the script checks the fragment against an allowlist and rejects (exit 64, the file is not touched) anything else, such as scripts, styles, `on…=` handlers, `javascript:`, comments, page structure tags, a loose `<` (write `&lt;`, which passes), tags left open (`<b/>` leaves it open: close it with `</b>`; only `<br/>` and `<hr/>` self-close; `</br>` does not pass), links to another site without a scheme (`//host`) or a tag left half written at the end (`<b`). Its message says what was wrong: fix the fragment and try again.

## 3. Add it

```bash
python3 scripts/agents/bitacora_add.py add --topic "<topic>" --entry <fragment.html> [--into <slug> | --new]
```

It prints `ok: new <slug> <path>` (new section) or `ok: append <slug> <path>` (entry below). Exit 3: there are similar sections and you did not pass `--into` or `--new` (back to step 1). Exit 65: the file was edited by hand and lost its markers; it is not touched: tell the person.

Write the fragment in a temporary file outside the repo and delete it afterwards. Do not edit `docs/bitacora.html` by hand: the script is what guarantees that nothing above is rewritten.

## 4. Tell the person

One line with the section and the link: `docs/bitacora.html#<slug>`. The file is versioned: commit it on the branch you are working on, or tell the person it is left to commit. Do not open a PR only for the log unless they ask.

Design tokens: `scripts/agents/bitacora/barrilete.css`; a project overrides them in its own .barrilete/bitacora.css, read when the page is created. The full detail is in the kit's log doc (docs/agents/bitacora.md, not installed in `--small` mode).

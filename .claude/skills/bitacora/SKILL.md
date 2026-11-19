---
name: bitacora
description: Draws the idea being thought through in this chat as an entry of the project log (docs/bitacora.html and one page per month in docs/bitacora/), in the section of a topic, with drawings, little text and plain words, to keep thinking it through and to record how it was reached. Only when the person asks, with "/bitacora <topic>", "save this in the log", "add it to the bitácora".
---

# Project log (`/bitacora <topic>`)

The project has **one** log, versioned in git so every member has it, split by month: `docs/bitacora.html` is the front page (the index of months and one section per topic, with a link to each month where the topic has entries) and the entries live in the page of their month, `docs/bitacora/YYYY-MM.html`, one section per topic. Each `/bitacora <topic>` adds an entry, with its date, **below** what that topic already had this month. Nothing that was written is rewritten: `scripts/agents/bitacora_add.py` only inserts, only writes the newest month's page (the ones before it are not touched) and creates the pages the first time. A log from before the split (all the entries in `docs/bitacora.html`) is moved unchanged to `docs/bitacora-anterior.html` with the first new entry, and the front page links it.

Run it only when the person asks for it. The log is for **thinking ideas through**, not for reporting work: what was touched, how it was checked and what failed are already in the PRs and the retros. The entry draws the idea being discussed in **this conversation** so the person can keep thinking about it and, once it is built, it records how it was reached. It is for a person who does not read code.

## 1. Find the section

```bash
python3 scripts/agents/bitacora_add.py find --topic "<topic>"
```

- `exact <slug>` (exit 0): the topic exists, in any month; the entry goes below (if the topic has no section in this month's page yet, it gets one).
- `none <slug>` (exit 0): there is no topic; its section is created at the end.
- `similar <slug>\t<topic>` (exit 3), one line per section with a similar name: **ask the person before writing**, naming the sections it found ("Do you mean the section «Decide the route», or is it a new one?"). Their answer decides the flag of step 3: `--into <slug>` for an existing section, `--new` for a new one. Without an answer, do not write.

If no `<topic>` was given, propose one in a few words from the conversation and confirm it before step 3.

## 2. Write the entry

A file with an HTML fragment (no `<html>`, `<head>` or `<body>`), in the language of the installation (`language` in `.agent-kit.json`; `en` without it). Do not repeat the date or the topic: the script writes them.

How to write it:
- **Drawings first.** Start with a drawing (steps, branches, map, comparison) and then the text that explains it. If something can be shown, do not tell it.
- **Little text.** Short sentences: what each part does and why.
- **Links.** The entry lives in `docs/bitacora/`: a link to another topic is `../bitacora.html#<slug>` (its section on the front page, with its months), and a relative link to a doc needs `../` in front.
- **Plain words,** no file names, paths, commands, functions, exit codes or PR or commit numbers. If a part of the system matters, name it by what it does ("the step that checks the entry"), not by its file.
- **The whole path of the idea:** where it came from, which options there were, what was dropped and why, what was decided and what is missing, with who has to decide.

What goes in, in this order, leaving out what does not apply:
1. **How it works**, with a flow or a map of parts: the entry starts with this drawing.
2. **The idea in one sentence**, in a note right below it.
3. **The options**: a branch diagram, with the chosen one and the dropped ones, and why.
4. **What was decided** and **what is missing**, with cards by status.

Components (the page already has their styles and they use the design tokens):

| Component | What for | HTML |
|---|---|---|
| Branch diagram | a question and its options | `<div class="branch"><div class="root">Where is it kept?</div><div class="opts"><div class="opt ok"><h4>One file</h4><p>Chosen: …</p></div><div class="opt danger"><h4>One per topic</h4><p>Dropped: …</p></div></div></div>` |
| Map of parts | how the parts connect | `<ul class="map"><li><span class="node">The chat</span><span class="edge">writes to</span><span class="node">The log</span></li></ul>` |
| Flow | steps in order | `<ol class="flow"><li>we talk</li><li>it is drawn</li><li>we decide</li></ol>` |
| Table | compare | `<table class="tbl"><tr><th>Before</th><th>After</th></tr><tr><td>…</td><td>…</td></tr></table>` |
| Cards by status | decided, in progress, waiting on you | `<div class="cards"><div class="card ok"><h3>Decided</h3><p>…</p></div><div class="card warn"><h3>In progress</h3><p>…</p></div><div class="card danger"><h3>Waiting on you</h3><p>…</p></div></div>` |
| Key numbers | a number that matters | `<div class="kpis"><div class="kpi ok"><b>3</b> steps</div></div>` |
| Bars | proportions, progress | `<div class="bars"><div class="bar ok"><span>Done</span><i style="--v:70%"></i></div></div>` |
| Note | the idea in one sentence, a warning | `<div class="note"><p><strong>The idea.</strong> …</p></div>` |
| Status in text | | `<span class="ok">done</span>`, `<span class="warn">in progress</span>`, `<span class="danger">waiting on you</span>` |

In `.opts` put only `.opt` items, two or three: the lines that join them assume that.

A page created before the diagrams does not have their styles (the design is copied when it is created): if the `<style>` of the month's page (`docs/bitacora/YYYY-MM.html`) has no `.branch{` or `.map{` rule (look for the rule, not the word, which can be in an entry), draw the options with cards or a table and the parts with a flow.

Status colors: `ok` done or chosen, `warn` in progress, `danger` waiting on a person, broken or dropped. Never only the color: the word says it too. In a map, `node` also takes `ok`, `warn` and `danger`.

Use only these components and plain text tags (`p`, `strong`, `em`, `ul`/`ol`/`li`, `a href`, `h3`, `h4`…): the script checks the fragment against an allowlist and rejects (exit 64, the file is not touched) anything else, such as scripts, styles, `on…=` handlers, `javascript:`, comments, page structure tags, a loose `<` (write `&lt;`, which passes), tags left open (`<b/>` leaves it open: close it with `</b>`; only `<br/>` and `<hr/>` self-close; `</br>` does not pass), links to another site without a scheme (`//host`) or a tag left half written at the end (`<b`). Its message says what was wrong: fix the fragment and try again.

## 3. Add it

```bash
python3 scripts/agents/bitacora_add.py add --topic "<topic>" --entry <fragment.html> [--into <slug> | --new]
```

It prints `ok: new <slug> <path>` (new topic) or `ok: append <slug> <path>` (the topic already existed, in any month); `<path>` is the month's page. Exit 3: there are similar sections and you did not pass `--into` or `--new` (back to step 1). Exit 64 also with a `--date` in the future or from a month before the newest page: the pages of past months are not touched. Exit 65: a page was edited by hand and lost its markers, or `docs/bitacora-anterior.html` already exists and the old log cannot be moved there; nothing is touched: tell the person.

Leave out `--date` (today in UTC) unless the person asks for another day of this month.

Write the fragment in a temporary file outside the repo and delete it afterwards. Do not edit `docs/bitacora.html` or the pages in `docs/bitacora/` by hand: the script is what guarantees that nothing above is rewritten.

## 4. Tell the person

One line with the section and the link: `docs/bitacora/YYYY-MM.html#<slug>`. The files are versioned: commit the front page and the month's page (and `docs/bitacora-anterior.html`, if it was just moved) on the branch you are working on, or tell the person they are left to commit. Do not open a PR only for the log unless they ask.

Design: `scripts/agents/bitacora/barrilete.css`, one for every project that uses barrilete-kit and always light; a project does not change it. The full detail is in the kit's log doc (docs/agents/bitacora.md, not installed in `--small` mode).

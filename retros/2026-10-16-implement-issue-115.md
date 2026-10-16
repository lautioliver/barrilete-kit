---
skill: implement-issue
issue: 115
pr: 138
area: docs
paths: AGENTS.md, docs, scripts/agents/check-docs.py, scripts/init-template.sh, scripts/test-init.sh
skill_sha: 82c8d03c29004251266bd65ada133c7e75df7ddb
date: 2026-10-16
model: sonnet
role: implementer
agent_sha: f274277c73a24eacd2f80eafae4cc305b64f6f61
---
**Deviations:** red tests first this time (red.sh on test-i18n and test-init). Wasted two verify runs (~25 min each) on test mistakes that a quick copy-and-run would have caught: init test comparing profile files with unsubstituted placeholders, and check-docs referencing a function outside the guarded block (broke small mode). Edited files while a red.sh run was copying the tree: avoided by drafting in the scratchpad.
**Decisions not covered:** translating a doc exposed code that parses Spanish prose (the ".env* ignorado" check, status.sh greps on AGENTS.md, init perl edits, "TODO: completar"); llms.txt had no sibling mechanism so I added llms.es.txt. Commit-description language (R-6) kept as in the Spanish text; needs an init substitution to follow --lang.
**What the review found:** commit-language rule drift, llms basename too broad, DELETE .txt sibling.
**Proposal:** a skill note: when translating prose, grep scripts for the Spanish strings they parse before writing the English file.

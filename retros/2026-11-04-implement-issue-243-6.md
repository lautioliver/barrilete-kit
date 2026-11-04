---
skill: implement-issue
issue: 243
pr: 247
area: ci
paths: .github/workflows/labels.yml, docs/decisions/kit/ADR-002-structured-red-validation.md, docs/decisions/kit/ADR-002-structured-red-validation.es.md
date: 2026-11-04
skill_sha: 672b483ae68026ab0dcfaa6b49cb841facbe9eb7
model: sonnet
role: session
---
**Deviations:** 4.ª review aplicada sin red aparte: son un permiso de workflow (config, sin comportamiento que testear en el fake) y citas en el ADR. Un `git commit -a` con paths falló y el commit de docs arrastró los 3 archivos; lo rehice con reset --soft y dos commits separados. No empujé: la persona pidió parar antes (toca workflows). Además, un `cat >` sin stdin colgó la primera corrida de la retro varios minutos.
**Decisions not covered:** en D9 conservé la cita del comentario 6636320504 para la enmienda y reemplacé la del alcance por 6637399247; la persona solo pidió citar el nuevo para el alcance.
**What the review found:** 4.ª review: faltaba `contents: read` para `pulls.listCommits`; el alcance (cualquier `<details>`) se confirmó como está.
**Proposal:** verify.py tarda ~10 min (i18n 411s); correrlo en background desde el principio.

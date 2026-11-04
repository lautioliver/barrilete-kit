---
skill: implement-issue
issue: 243
pr: 247
area: infra
paths: .github/workflows/labels.yml, scripts/agents/test-labels-check.sh
date: 2026-11-04
skill_sha: 672b483ae68026ab0dcfaa6b49cb841facbe9eb7
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** none. Cierre de la 3.ª review: el cuerpo se actualizó después del push de la persona (CI exige que los sha del bloque ya sean commits del PR); CI verde (labels, pr-title, docs).
**Decisions not covered:** los tests de regresión agregados después del arreglo (`f479d2b`) no tienen rojo propio porque el arreglo ya estaba commiteado; lo verifiqué contra el `labels.yml` viejo (fallan) y lo dije en el cuerpo. La skill no dice cómo tratar ese caso.
**What the review found:** (ver retro anterior de este run) contar tags como substrings y fences sin CommonMark; arreglado con `etiquetas` y `enFence`.
**Proposal:** `red.sh` bajo carga rechaza el rojo por tests de performance viejos; avisar o reintentar. Probar `pulls.listCommits` con solo `pull-requests: read` antes de mergear.

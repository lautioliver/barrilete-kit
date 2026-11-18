---
skill: implement-issue
issue: 341
pr: 346
area: infra
paths: scripts/agents/checks/pr-metadata, scripts/agents/test-checks.sh
date: 2026-11-18
skill_sha: 27a1947ee312dc9fbbcf418c7af4aa075868ae73
model: opus
role: session
---
**Deviations:** abrí el PR con verify.py diciendo "Some checks fail" sin mirar cuál: miré solo el final de la salida y supuse que era pr-metadata, que antes del PR no verifica. Era `tap` (test-tap.sh: un id con `$` en una línea del fixture). Lo arreglé en un commit aparte, después de abrir el PR.
**Decisions not covered:** cómo poner en un fixture un id con `\$` sin que la regla de test-tap ("el id es un literal") lo tome por un id dinámico. La línea se arma con `printf '%s …' tap_check`; la regla mira el fuente con un grep y no distingue un heredoc de fixture de un caso real.
**What the review found:** /code-review (low): nada.
**Proposal:** que implement-issue diga que, antes de abrir el PR, se mire en la salida de verify.py qué checks fallaron (líneas FAILED), y que "not verified" de pr-metadata es lo único que se acepta antes de abrirlo.

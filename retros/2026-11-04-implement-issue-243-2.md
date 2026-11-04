---
skill: implement-issue
issue: 243
pr: 247
area: agents
paths: .github/workflows/labels.yml, scripts/agents/test-labels-check.sh, .claude/skills/implement-issue/SKILL.md, docs/decisions/kit/ADR-002-structured-red-validation.md
date: 2026-11-04
skill_sha: 8df831c256550158c7b1cc7b6d93d41729a49dc3
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** none. Retomé tras un corte de sesión (tmux): los commits 88dd1ae (rojo), ffe3e8c y 8df831c ya estaban; los revisé, re-corrí `red.sh bash` sobre 88dd1ae (4 casos rojos, todos aserciones nuevas), los tests (0 fallas) y `verify.py`. No empujé: toca `.github/workflows` y el bot no puede.
**Decisions not covered:** al rehacer el bloque del rojo para una corrección de review, reemplacé el bloque principal por el del nuevo red commit y dejé el primero (4daac60) listado en "How to test it". La skill no dice si, en una corrección de review, se conserva también el rojo original como `<details>` extra (con el mismo stack, no se sabe si el CI lo acepta).
**What the review found:** el chequeo de `red commit:` miraba todo el cuerpo (prosa, `red commit: ninguno` junto a `no tests:`, bloques de código) y duplicaba el error de no-hex; se acotó al bloque del rojo.
**Proposal:** documentar en implement-issue qué hacer con el bloque del rojo cuando una review pide otro rojo, y cómo retomar una sesión cortada con commits sin empujar.

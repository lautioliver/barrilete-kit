---
skill: implement-issue
issue: 356
pr: 357
area: infra
paths: scripts/agents/worktree-lock.sh, scripts/agents/test-worktree-lock.sh, .claude/skills/implement-issue, .claude/skills/review-pr, docs/agents/subagent-contract.md
date: 2026-11-18
skill_sha: 57d4b480e022de41a606724e26099e529bc53861
model: opus
role: session
---
**Deviations:** Dos casos nuevos (mutex vivo con release y handoff) pasaban aunque rompiera el código: el candado de antes era de otro agente, así que el claim de preparación no tomaba nada, y el caso de handoff corría después de que release ya lo había borrado. Lo encontré con una mutación a mano antes del PR. El `/code-review` también vio que las guardas `-n` de `recibe` no tenían un caso propio.
**Decisions not covered:** El issue dejaba abierto el enfoque. La persona eligió en el chat traspaso explícito y después, entre tres variantes, la reserva con token (dos preguntas, no una). `bk handoff` vive en barrilete-workspace: quedó como propuesta en el PR, sin tocar bk.
**What the review found:** Token en texto plano en el candado (ahora guarda el sha256), un nombre de agente con salto de línea que plantaba un `handoff=`, el skill que mandaba a soltar al final aun después de pasar el candado, un temporal inútil en release y guardas redundantes. Sin cambio, explicados en el PR: prepare.sh con el token exportado, la regla generada de implementer.md y la salida de handoff sobre un candado libre.
**Proposal:** Al agregar un campo a un archivo que se arma con datos del entorno (nombres, rutas), revisar que nada del entorno pueda escribir ese campo; acá el campo nuevo volvió peligroso un salto de línea que antes era inofensivo.

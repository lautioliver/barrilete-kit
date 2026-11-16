---
skill: implement-issue
issue: 322
pr: 329
area: docs
paths: docs/decisions/kit/ADR-007-per-project-learning.md, docs/decisions/kit/ADR-006-rules-store-for-agents.md, docs/README.md, docs/llms.txt
date: 2026-11-16
skill_sha: 2459b4d65d63ee3b83477a38543f06580fb8a3be
model: opus
role: session
---
**Deviations:** pedí review con el primer CI en rojo: verify.py corre check-docs solo en el repo del kit, no sobre el proyecto que genera init. Dos fallas de test-init.sh que no vi antes del push: (1) en el modo chico, una ruta `docs/development/horizon.md` citada en el ADR no existe; (2) con `--lang`, el link de ADR-006.es a `ADR-007-…es.md` se rompía. Las arreglé con dos commits y test-init pasa en local (136 ok).
**Decisions not covered:** el issue pedía tocar horizon.md y architecture.md, pero en el kit son plantillas que init copia a los proyectos. Le pregunté a la persona y eligió dejar la fase 5 en el ADR. También: `unknown` para el modelo y el harness cuando el emisor no los conoce (queda como pregunta abierta), y que D4 deja a `/improve-skills` sin issue que lo implemente.
**What the review found:** `/code-review` low no dio hallazgos y no leyó el texto (diff solo de docs). Las fallas de CI las encontró el CI.
**Proposal:** cuando un PR toca `docs/decisions/kit/` o los índices, que implement-issue (o el `verify` del mapa) corra `scripts/test-init.sh` antes del push. Esos archivos se instalan en los proyectos, y check-docs del kit no ve los modos chico ni `--lang`.

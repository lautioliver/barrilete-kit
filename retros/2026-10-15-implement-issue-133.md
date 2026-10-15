---
skill: implement-issue
issue: 133
pr: 134
area: infra
paths: scripts/update.py, scripts/grow.py, scripts/test-install.sh, CHANGELOG.md
skill_sha: 82c8d03c29004251266bd65ada133c7e75df7ddb
date: 2026-10-15
model: sonnet
role: implementer
agent_sha: f274277c73a24eacd2f80eafae4cc305b64f6f61
---
**Desvíos:** ninguno. El test de grow + update falló al principio por la razón equivocada (update.py frenaba por archivos en pending que dejó grow); hubo que limpiar pending en el fixture para que fallara por la aserción.
**Decisiones no cubiertas:** dónde poner los tests (test-install.sh, que ya tiene las plantillas con tags); el test viejo "grow.py conserva ref" cambió de expectativa porque el HEAD clonado ya no coincide con el ref instalado.
**Lo que encontró la revisión:** /code-review corrió primero en el checkout equivocado (rango vacío); hubo que pasarle la ruta del worktree. 7 hallazgos: se corrigieron el stderr de merge-base y el test de recuperación; el resto se dejó por ser lo que pide el issue o fuera de alcance.
**Propuesta:** que el contrato diga cómo invocar /code-review desde un worktree distinto del cwd de la sesión.

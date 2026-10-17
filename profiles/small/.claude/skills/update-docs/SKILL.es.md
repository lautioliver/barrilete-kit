---
name: update-docs
description: Detecta qué documentación quedó desactualizada por un cambio y la corrige en el mismo PR. Usar antes de abrir un PR (implement-issue la llama), con "/update-docs", "actualizá los docs" o "¿qué docs quedaron viejos?".
---

# Actualizar docs

Los agentes trabajan con lo que dicen los docs: si un doc dice algo que el código ya no hace, el próximo agente construye sobre algo falso. Si un doc y el código no coinciden, **gana el código** (salvo un ADR: ahí se consulta).

1. **Mirá el diff:** `git diff <BASE_BRANCH>...HEAD --stat` y después el detalle.
2. **Revisá contra cada doc:**
   - ¿Cambió algo que corre (pantallas, endpoints, datos, flujos, deploy)? → `docs/architecture.md`.
   - ¿Cambió un comando, una dependencia o una convención? → `AGENTS.md`.
   - ¿Cambió una decisión de un ADR? → no lo reescribas: enmienda con fecha o ADR nuevo (`docs/decisions/README.md`). Consultalo antes.
   - ¿Agregaste un documento? → `docs/README.md` y `docs/llms.txt`.
3. **Escribí lo mínimo:** describí lo que hay, no la historia del cambio (eso va en el PR). No inventes lo que no está en el código.
4. **Validá:** `python3 scripts/agents/check-docs.py`.
5. **Reportá** en el PR qué docs cambiaste, o por qué no hizo falta.

Para "¿qué docs quedaron viejos?": corré `check-docs.py`, después compará `docs/architecture.md` y `AGENTS.md` con el código y listá los desfases con archivo y línea.

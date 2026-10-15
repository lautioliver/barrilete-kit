---
name: update-docs
description: Detecta qué documentación quedó desactualizada por un cambio y la corrige. Usar antes de abrir un PR (implement-issue la llama), con "/update-docs", "actualizá los docs", "¿qué docs quedaron viejos?" o para corregir desfases entre docs y código.
---

# Actualizar docs

Los agentes trabajan con lo que dicen los docs. Si un doc dice algo que el código ya no hace, el próximo agente va a construir sobre algo falso. Esta skill mantiene los docs al día con el código.

Regla de fondo (`docs/README.md`): si un doc y el código no coinciden, **gana el código** y se corrige el doc. Excepción: si el doc es un ADR, el código puede estar mal; ahí se consulta.

## Modo 1: después de un cambio (lo normal)

1. **Qué tocar:**
   ```bash
   python3 scripts/agents/agents_map.py            # rama actual contra la base
   python3 scripts/agents/agents_map.py --pr <n>   # o un PR
   ```
   Lista los docs que el mapa (`docs/agents-map.json`) asocia a los archivos cambiados, marcando los que siguen **SIN MODIFICAR**.
2. **Revisar cada uno** contra el diff (`git diff <base>...HEAD`). El mapa sugiere; vos decidís. Un doc listado puede no necesitar cambios (el cambio no altera lo que describe), y un doc no listado puede necesitarlos.
3. **Además del mapa**, revisá siempre:
   - ¿Cambió un comando o una convención? → `AGENTS.md`.
   - ¿Cambió una decisión de un ADR? → no lo reescribas: enmienda con fecha o ADR nuevo (`docs/decisions/README.md`). Esto requiere consultar (AGENTS.md, Autonomía).
   - ¿Agregaste un documento con contenido? → `docs/README.md` y `docs/llms.txt`.
   - ¿Un término nuevo del dominio? → `docs/reference/glossary.md`.
4. **Escribir.** Cambios mínimos y precisos: describí lo que hay, no la historia del cambio (eso va en el PR). No dupliques listas canónicas: si la lista vive en otro archivo, enlazala.
5. **Validar:**
   ```bash
   python3 scripts/agents/check-docs.py
   ```
6. **Reportar** qué docs cambiaste y cuáles del mapa decidiste no tocar y por qué. Esto va en el PR.

## Modo 2: auditar desfases viejos

Con "¿qué docs quedaron viejos?" o "revisá que architecture.md esté al día":

1. Corré `check-docs.py` (links y rutas rotas son el síntoma más barato).
2. Por cada doc de `docs/reference/` y `docs/development/architecture.md`, compará lo que afirma con el código: endpoints, tablas, módulos, comandos. Priorizá lo que un agente usaría para decidir.
3. Listá los desfases encontrados con archivo y línea. Los chicos, corregilos en un PR `docs(docs): …`; los grandes, como issues (`create-issue`, `type:docs`).

## No hacer

- No inventar comportamiento que no está en el código ni en el diff.
- No mover contenido de `horizon.md` o `roadmap.md` a `architecture.md` si no está implementado.
- No reescribir ADRs aceptados.

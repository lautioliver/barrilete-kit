# ADR-001 — Idioma del kit: labels, archivos y claves en inglés, prosa en dos idiomas

## Estado

Aceptado (2026-10-15)

Ámbito: kit

Aplicación: hasta que se mergee cada issue de la épica #111, rigen los nombres, labels e idioma actuales (`tipo:`, `logica-negocio`, descripciones de commit en español). Nadie usa los nombres nuevos antes de que su issue los introduzca; `AGENTS.md`, `docs/convencion-nombres-github.md` y `labels.yml` se alinean issue por issue.

Origen: épica #111 e issue #112. Decisiones D1–D6 aprobadas por @lautioliver en el chat el 2026-10-15.

## Contexto

- El kit tiene unas 25.000 palabras en 51 `.md`, todas en español. Solo el README tiene versión en inglés (`README.en.md`, #55).
- 43 archivos tienen nombre en español (`scripts/agentes/`, `preparar.sh`, `barandas.py`, `docs/mapa-agentes.json` con claves `cuando`, `revisar`…).
- Los labels (`tipo:`, `estado:`, `prioridad:`, `logica-negocio`) están cableados en unos 15 scripts y workflows (`ruteo.py`, `planificar.py`, `equipo.py`, `disponibles.sh`, `estado.sh`, `labels.yml`, `desbloquear.yml`, `labeler.yml`, plantillas de issue).
- Se quiere ofrecer el kit en inglés y en español. Mantener dos kits enteros duplicaría el trabajo; mezclar idiomas en los identificadores obliga a los scripts a conocer ambos.
- El kit está en 0.x: todavía se pueden romper nombres sin violar compatibilidad.

## Decisión

1. **R-1 (D1). La prosa se publica en dos idiomas como archivos hermanos.** `X.md` en inglés y `X.es.md` en español (por ejemplo `SKILL.md` y `SKILL.es.md`). Aplica a lo que se lee (README, guías, landing) y a lo que se instala (`AGENTS.md`, skills, `docs/`, plantillas de issue y PR). `init-plantilla.sh --lang es` reemplaza cada `X.md` por su `X.es.md` y borra los hermanos; con `en` (default) borra los `.es.md`. Combina con `--chico` sin perfiles nuevos: `perfiles/chico/` también tiene hermanos. Un check de `check-docs.py` falla si una versión quedó atrás (mismo número de encabezados y de bloques de código, como mínimo; el detalle lo define #113).
2. **R-2 (D2). Los labels son siempre en inglés, en los dos idiomas.** `type:`, `area:`, `priority:`, `status:`, `business-logic`, `breaking-change`. Son identificadores, como los tipos de commit. Los proyectos en 0.9 migran con `aliases` de label-sync, que conserva los labels ya puestos en los issues.
3. **R-3 (D3). Archivos, rutas y claves JSON van en inglés.** Por ejemplo scripts/agents/guardrails.py (a crear), docs/agents-map.json (a crear), claves `when` y `review`. Solo se traduce la prosa. `actualizar.py` lleva una tabla de renombres para proyectos en 0.9.
4. **R-4 (D4). Los mensajes de los scripts salen solo en inglés.** No se traducen ni se parametrizan por idioma.
5. **R-5 (D5). Los cambios con ruptura (R-2, R-3) entran antes del tag `v1.0.0`.** En 0.x se puede romper compatibilidad. El issue #91 queda bloqueado por la épica #111.
6. **R-6 (D6). La descripción de commits y los títulos de PR van en el idioma de instalación.** Los tipos y scopes de Conventional Commits siguen en inglés. Hoy `AGENTS.md` fija español; pasa a depender de `--lang`.
7. **R-7. Los ADRs del kit no son los del proyecto.** Un ADR con la línea exacta `Ámbito: kit` (debajo de `## Estado`, ver `decisions/README.md`) explica por qué el kit es como es y vive solo en este repo. `init-plantilla.sh` (modo completo y `--chico`) borra esos ADRs y las líneas que los listan en `docs/README.md` y `docs/llms.txt`, que van entre marcadores `<!-- plantilla:inicio -->` y `<!-- plantilla:fin -->`; el proyecto numera los suyos desde `ADR-001` y conserva el TODO de su primer ADR. `actualizar.py` y `crecer.py` inicializan con el mismo init, así que el filtro les llega: un proyecto en 0.9 con su propio `ADR-001` no recibe el del kit. Esto ya está implementado y probado en `scripts/test-init.sh`. Los ADRs de proyectos instalados no llevan el ámbito.

## Alternativas descartadas

- **Un solo idioma (español).** Deja afuera a quien no lee español y no resuelve la duplicación entre `README.md` y `README.en.md`.
- **Un solo idioma (inglés).** Pierde a los equipos que trabajan en español, que son el público actual.
- **Directorios por idioma (`docs/en/`, `docs/es/`).** Rompe las rutas que los scripts, el mapa y los links dan por fijas, y separa cada archivo de su traducción, lo que facilita la desincronización.
- **Ramas o repos por idioma.** Duplica el mantenimiento de todo el kit.
- **Labels traducidos por idioma.** Los scripts y workflows tendrían que resolver dos vocabularios, y un proyecto no podría cambiar de idioma sin migrar labels.
- **Mensajes de scripts traducidos.** Multiplica el mantenimiento por poco valor: los lee quien opera el kit, y los modelos trabajan igual con inglés.
- **Dejar los nombres de archivos en español.** Los labels en inglés y las rutas en español mezclarían idiomas en los identificadores sin ganar nada.

## Consecuencias

- Se gana: un kit con un solo juego de identificadores y dos juegos de prosa, y una instalación que elige idioma sin tocar scripts.
- Cuesta: cada documento se mantiene dos veces, con el check de paridad como red. Los renombres rompen a los proyectos en 0.9.
- Tabla de renombres de labels (con `aliases` en `labels.yml`):

| 0.9 | Nuevo |
|---|---|
| `tipo:*` | `type:*` (los valores de tipo, `bug`, `docs`… se revisan en #114: los que ya son inglés quedan igual) |
| `area:*` | `area:*` (sin cambio) |
| `prioridad:critica`, `alta`, `media`, `baja` | `priority:critical`, `high`, `medium`, `low` |
| `estado:a-triar`, `necesita-info`, `bloqueado` | `status:triage`, `needs-info`, `blocked` |
| `logica-negocio` | `business-logic` |
| `breaking-change` | `breaking-change` (sin cambio) |

- Tabla de renombres de archivos (la completa se arma en el issue de `actualizar.py`; ejemplos):

| 0.9 | Nuevo |
|---|---|
| `scripts/agentes/` | `scripts/agents/` |
| `scripts/agentes/barandas.py` | scripts/agents/guardrails.py (a crear) |
| `docs/mapa-agentes.json` | docs/agents-map.json (a crear) |
| `preparar.sh` | `prepare.sh` |
| claves `cuando`, `revisar` | `when`, `review` |

- Hay que cambiar código, workflows y docs en los issues de la épica #111 (traducción, renombres, labels, init `--lang`, `actualizar.py`, check de paridad). Este ADR no renombra ni traduce nada.
- `docs/convencion-nombres-github.md` pasa a nombrar los labels en inglés cuando se haga el issue de labels.
- Cambiar R-2 o R-3 después de `v1.0.0` exigiría otra migración: se trata como ruptura y pide un ADR nuevo.

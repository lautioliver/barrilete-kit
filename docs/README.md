# Documentación de <PROJECT>

TODO: qué es <PROJECT> en una frase, con link al ADR que lo define.

Esta carpeta es el mapa. El código es la verdad de lo que corre; acá se dice **dónde leer** y **qué no mezclar**.

---

## Cómo leer (elegí un camino)

| Quién | Empezá acá | Después |
|---|---|---|
| Persona nueva en el equipo | Este archivo → [glosario](reference/glossary.md) → [recorridos](reference/journeys.md) | [setup](development/setup.md) y a correr |
| Producto / negocio | [Visión](development/vision.md) → [Spec](../README.md) → [roadmap](development/roadmap.md) | [horizonte](development/horizon.md) (no es el próximo ticket) |
| Ingeniería (qué hay hoy) | [arquitectura](development/architecture.md) → [módulos](reference/modules.md) → [dominio](reference/domain.md) | [superficies](reference/surfaces.md) |
| Deploy | [deploy](development/deploy.md) | ADRs de infraestructura |
| Agente / LLM | [`llms.txt`](llms.txt) y [`AGENTS.md`](../AGENTS.md) | No inventar schema ni roadmap |

Regla: si un documento de producto y el código no coinciden, **gana** [architecture.md](development/architecture.md). El [README](../README.md) es spec (incluye lo que viene). La [visión](development/vision.md) resume qué es, qué hay y qué viene. El [horizonte](development/horizon.md) es conversación de largo plazo.

---

## Capas de verdad

| Capa | Archivo | Sirve para |
|---|---|---|
| Spec | [`README.md`](../README.md) | Qué queremos que el producto sea |
| Visión | [`development/vision.md`](development/vision.md) | Qué es / qué hay / qué viene (narrativa) |
| Ahora | [`development/architecture.md`](development/architecture.md) | Qué está implementado |
| Orden | [`development/roadmap.md`](development/roadmap.md) | Qué se construye y en qué orden |
| Después | [`development/horizon.md`](development/horizon.md) | Ideas de largo plazo — **no implementar** |
| Por qué | [`decisions/`](decisions/) | ADRs |
| Cómo se levanta | [`development/setup.md`](development/setup.md) | Dev local |
| Cómo se publica | [`development/deploy.md`](development/deploy.md) | Entornos y deploy |
| Cómo se integra | [`guides/`](guides/) | Integraciones con terceros |
| Mapa | [`reference/`](reference/) | Glosario, datos, pantallas, módulos, recorridos |

---

## Índice

### Referencia

- [Glosario](reference/glossary.md) — palabras que no se cambian
- [Dominio y datos](reference/domain.md) — tablas, IDs, estados
- [Superficies](reference/surfaces.md) — URLs y quién entra
- [Módulos](reference/modules.md) — dónde vive cada cosa en el código
- [Recorridos](reference/journeys.md) — de punta a punta, con archivos

### Desarrollo

- [Setup](development/setup.md)
- [Arquitectura implementada](development/architecture.md)
- [Visión](development/vision.md)
- [Roadmap](development/roadmap.md)
- [Horizonte](development/horizon.md)
- [Deploy](development/deploy.md)
- Auditorías: `development/audit-<tema>-<AAAA-MM-DD>.md`. Cada hallazgo con ID estable (`AUD-01`…) para poder abrir un issue por hallazgo.

### Decisiones

- [Cómo se escribe un ADR](decisions/README.md)
<!-- template:start -->
- [ADR-001 (kit)](decisions/ADR-001-language-labels-and-names-in-english.md) — idioma del kit: prosa en dos idiomas, labels y nombres en inglés (ADR del kit: el init no lo instala)
<!-- template:end -->
- TODO: `- [ADR-001](decisions/ADR-001-....md) — resumen en una línea`

### Guías

- TODO: una guía por integración.

### Agentes

- [`AGENTS.md`](../AGENTS.md) — convenciones cortas para quien toca el repo
- [`llms.txt`](llms.txt) — índice compacto para modelos
- [`github-naming-convention.md`](github-naming-convention.md) — ramas, commits, PRs, issues y labels ([`.github/labels.yml`](../.github/labels.yml))
- [`agents-map.json`](agents-map.json) — qué docs revisar según lo que cambia, rutas sensibles y docs obligatorios
- [`agents/subagent-contract.md`](agents/subagent-contract.md) — reglas y formato de salida de los subagentes de `.claude/agents/` (implementador, implementador liviano, revisor)
- [`agents/lessons.md`](agents/lessons.md) — lo aprendido de las retros de los agentes, revisado en un PR (las retros crudas viven en la rama `agentes/retros`)
- Skills en [`../.claude/skills/`](../.claude/skills/): `plan-feature`, `create-issue`, `implement-issue`, `debug`, `db-migration`, `update-docs`, `review-pr`, `status`, `git-workflow`, `improve-skills`, `orchestrate`
- Los docs se validan en CI: [`../scripts/agents/check-docs.py`](../scripts/agents/check-docs.py)

---

## Cómo mantener esta sección

- Cambio de **comportamiento que ya corre** → `architecture.md` y, si aplica, `reference/*`.
- Cambio de **orden de producto** → `roadmap.md`.
- Cambio de **narrativa qué es / qué hay / qué viene** → `vision.md`.
- Idea de **algún día** → `horizon.md`, no al código.
- Decisión irreversible → ADR nuevo en `decisions/`.
- Un ADR y el código no coinciden → actualizar el ADR o el código; no dejar los dos.
- Documento nuevo → sumarlo a este índice. A `llms.txt` se suma recién cuando tiene contenido (no solo `TODO:`).

No duplicar listas canónicas (endpoints, tablas): viven en un solo archivo y el resto enlaza.

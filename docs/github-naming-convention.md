# Convención de nombres en GitHub — <PROJECT>

> **Estado:** PROPUESTA — pendiente de decisión del equipo.
> **Fecha:** <DATE>
> **Alcance:** ramas, commits, pull requests, issues / ítems del Project, labels, campos del Project, milestones, tags y releases.
> **Para agentes:** una vez aprobado, este documento es la fuente de verdad. Ningún agente debe crear ramas, commits, PRs o issues con otro formato. Si algo no está cubierto, preguntar antes de inventar un formato nuevo.

Cada sección muestra las **opciones** que usa la industria, sus pros y contras, y una **recomendación**. Al final hay una tabla para marcar la decisión.

---

## 0. Resumen de la recomendación

| Elemento | Formato recomendado | Ejemplo |
|---|---|---|
| Rama | `<tipo>/<n°issue>-<descripcion>` (Conventional Branch 1.1) | `feat/42-vista-usuario-unificada` |
| Rama creada por agente | `claude/<n°issue>-<descripcion>` | `claude/57-auditoria-flujo-pago` |
| Commit | `<tipo>(<scope>): <descripcion>` (Conventional Commits 1.0) | `fix(checkout): evitar doble cobro al reintentar` |
| Título de PR | Igual que un commit + `Closes #n` en el cuerpo | `feat(usuario): unificar cuentas por email` |
| Título de issue | Imperativo, sin prefijo; el tipo va en *Issue Type* | `Unificar comprador, asistente y organizador bajo un mismo email` |
| Labels | Con prefijo `grupo:valor` | `area:checkout`, `priority:high` |
| Tag / release | SemVer con `v` | `v1.2.0` |
| Milestone | Hito de negocio o versión | `MVP evento 14-11` / `v1.0.0` |

---

## 1. Ramas

### Opción A — Git Flow clásico
Ramas permanentes `main` + `develop`, y temporales `feature/*`, `release/*`, `hotfix/*`.
- ✅ Muy conocido, separa claramente producción de desarrollo.
- ❌ Pesado para un equipo de 2: hay que mantener `develop` sincronizada y hacer ramas de release.

> ✅ **DECIDIDO (<DATE>):** ramas cortas con prefijo (Conventional Branch 1.1). <BRANCH_RULE>

### Opción B — GitHub Flow + Conventional Branch 1.1
Una sola rama permanente (`main`) y ramas cortas con el formato `<tipo>/<descripcion>`.

La especificación Conventional Branch define los prefijos `feature/` (alias `feat/`), `bugfix/` (alias `fix/`), `hotfix/`, `release/` y `chore/`, y desde la v1.1.0 agrega prefijos para ramas creadas por agentes de IA: `ai/`, `claude/`, `codex/`, `copilot/`, `cursor/`. Las ramas troncales (`main`, `master`, `develop`) no llevan prefijo.

Reglas de la spec:
- Solo minúsculas, números y guiones. Nada de espacios, `_` ni mayúsculas.
- Puntos solo en versiones: `release/v1.2.0`.
- Sin guiones dobles, ni al principio ni al final de la descripción.
- Incluir el número de ticket cuando exista.

- ✅ Estándar publicado, validable automáticamente (hay GitHub Action), se lleva bien con Conventional Commits.
- ✅ El prefijo `claude/` permite distinguir a simple vista qué trabajo hizo un agente — útil para auditar.
- ❌ Requiere disciplina con el n° de issue.

### Opción C — Ticket primero
`<n°issue>-<descripcion>` (es lo que genera GitHub con el botón "Create a branch" desde un issue).
- ✅ Cero fricción, trazabilidad perfecta con el issue.
- ❌ El nombre no dice qué tipo de cambio es; no hay estándar externo que lo respalde.

### Opción D — Por autor
`<usuario>/<descripcion>` (p. ej. `lautaro/login`).
- ✅ Se sabe de quién es cada rama.
- ❌ Esa información ya la da Git; no dice el propósito. Poco usado como estándar.

### Formato recomendado (B + número de issue)
```
<tipo>/<n°issue>-<descripcion-corta>
```

| Tipo | Cuándo | Ejemplo |
|---|---|---|
| `feat/` | Funcionalidad nueva | `feat/42-vista-usuario-unificada` |
| `fix/` | Corrección de un bug | `fix/51-qr-no-valida-offline` |
| `hotfix/` | Corrección urgente en producción | `hotfix/60-caida-pasarela-pago` |
| `chore/` | Dependencias, config, docs, tooling | `chore/58-actualizar-dependencias` |
| `release/` | Preparar una versión | `release/v1.0.0` |
| `claude/` | Rama creada por un agente de Claude | `claude/57-auditoria-flujo-pago` |

**Excepción: `agents/retros`.** Rama huérfana de larga vida donde los agentes guardan sus retros (un archivo por retro) con `.claude/skills/improve-skills/retro.sh`. Es una rama de datos: no lleva número de issue, no se mergea nunca y se escribe sin PR, siempre con ese script. Si el repo protege ramas con un patrón amplio (`*`), excluila, o las retros quedan pendientes en `.git/pending-retros/`. Los proyectos que vienen de 0.9 conservan la rama `agentes/retros`: se sigue leyendo (`/improve-skills`), nunca se escribe ni se borra.

> **Decisión a tomar:** ¿usamos los alias cortos (`feat/`, `fix/`) o los largos (`feature/`, `bugfix/`)? Recomendado: **cortos**, porque coinciden con los tipos de commit.

---

## 2. Commits

### Opción A — Conventional Commits 1.0 ⭐ recomendada
```
<tipo>(<scope opcional>): <descripcion>

[cuerpo opcional]

[footer opcional]
```
La spec solo obliga `feat` y `fix`; `fix` equivale a un PATCH en SemVer, `feat` a un MINOR, y `BREAKING CHANGE` (o `!` después del tipo) a un MAJOR. Los demás tipos (`docs`, `refactor`, `test`, `chore`, etc.) vienen de la convención de Angular y son los más usados.

| Tipo | Uso |
|---|---|
| `feat` | Funcionalidad nueva |
| `fix` | Corrección de bug |
| `refactor` | Cambio interno sin cambiar comportamiento |
| `perf` | Mejora de rendimiento |
| `test` | Tests |
| `docs` | Documentación (README, wiki, auditorías) |
| `style` | Formato, sin cambio de lógica |
| `build` | Build, dependencias |
| `ci` | Pipelines, GitHub Actions |
| `chore` | Mantenimiento que no encaja en lo anterior |
| `revert` | Revertir un commit |

- ✅ Estándar de facto; permite changelog y versionado automáticos.
- ❌ Hay que aprender la lista de tipos.

### Opción B — Gitmoji
`🐛 Arreglar validación de QR`.
- ✅ Visual y divertido.
- ❌ Menos estructurado, difícil de parsear, los emojis se ven distinto según la terminal.

### Opción C — Estilo libre en imperativo (guía de Chris Beams)
`Arreglar validación de QR`.
- ✅ Simple.
- ❌ Sin tipo ni scope, no automatizable.

### Scopes del proyecto
Los scopes deberían ser pocos y estables, y coincidir con los labels `area:`. Siempre existen `db`, `api` y `docs`.

TODO: `<scope-1>`, `<scope-2>`, `db`, `api`, `docs`

> Regla: si un cambio toca varios scopes, se omite el scope o se divide en varios commits.

### Reglas adicionales
- Descripción en imperativo, minúscula, sin punto final, ≤ 72 caracteres.
- Un commit = un cambio lógico.
- Cambios que rompen compatibilidad: `feat(api)!: ...` + footer `BREAKING CHANGE: ...`.
- Referenciar el issue en el footer: `Refs #42` o `Closes #42`.

---

## 3. Pull requests

### Opción A — Título = Conventional Commit + squash merge ⭐ recomendada
- Título del PR con el mismo formato que un commit: `feat(usuario): unificar cuentas por email`.
- Se mergea con **Squash and merge**, así el título del PR queda como el commit en `main`.
- Cuerpo con `Closes #42` para cerrar el issue automáticamente, o `Refs #42` si el PR es parte del issue pero no lo cierra (un diagnóstico, un paso de varios).
- ✅ Historial de `main` limpio aunque los commits intermedios sean desprolijos.

### Opción B — Título libre + merge commit
- ✅ Conserva todo el historial de la rama.
- ❌ `main` queda con commits de todo tipo; no sirve para changelog automático.

### Plantilla de cuerpo sugerida
```markdown
## Qué cambia
## Por qué
## Lógica de negocio afectada (¿modifica algo ya definido en auditorías?)
## Cómo probarlo
Closes #
```
> La sección "Lógica de negocio afectada" es clave para el objetivo del proyecto: obliga a declarar si el PR toca algo que ya se había fijado.

---

## 4. Issues e ítems del GitHub Project

### 4.1 Título

#### Opción A — Prefijo de tipo en el título
`[BUG] El QR no valida sin conexión` · `feat: vista de usuario unificada`
- ✅ Se ve el tipo en cualquier lista.
- ❌ Duplica información si ya se usan labels o issue types; los títulos quedan inconsistentes.

#### Opción B — Título en imperativo, tipo como metadato ⭐ recomendada
`Unificar comprador, asistente y organizador bajo un mismo email`
- El título describe **qué hay que lograr**, en imperativo, sin punto final, entendible para alguien que lo lea meses después.
- El tipo se marca con **Issue Type** (si el repo está en una organización) o con un **label `type:`** (si es un repo personal).
- ✅ Títulos limpios y filtrables.

#### Opción C — Título con ID de módulo
`[CHECKOUT] Evitar doble cobro al reintentar`
- ✅ Agrupa visualmente por área.
- ❌ Mismo problema de duplicación; mejor resolverlo con label `area:`.

**Para bugs** se acepta título descriptivo del síntoma en lugar de imperativo: `El QR no valida sin conexión`.

### 4.2 Tipo de issue

GitHub tiene **Issue Types** nativos, disponibles en general desde abril de 2025, con tres tipos por defecto: Task, Bug y Feature. Se configuran a nivel de organización (hasta 25 tipos).

| Situación | Qué usar |
|---|---|
| El repo está en una **organización** de GitHub | Issue Types: `Feature`, `Bug`, `Task` (+ opcional `Epic`, `Audit`) |
| El repo es **personal** | Labels `type:feature`, `type:bug`, `type:task`, `type:audit` |

> **Decisión a tomar:** ¿el repo está en una organización? Si no, conviene moverlo — Issue Types y varias funciones de Projects funcionan mejor así.

### 4.3 Jerarquía (sub-issues)
Usar **sub-issues** nativos en lugar de listas de tareas en el cuerpo:

```
Epic     →  Vista de usuario unificada
 └ Feature →  Login único por email
    └ Task  →  Migrar tabla de usuarios
```

### 4.4 Tipo propio: auditoría
Como el proyecto genera auditorías, se propone un tipo/label `audit` para los issues que nacen de una auditoría, con título:

`Auditoría <área>: <hallazgo>` → `Auditoría pagos: el webhook no es idempotente`

Y en el cuerpo el link al documento de auditoría correspondiente.

---

## 5. Labels

### Opción A — Labels por defecto de GitHub
`bug`, `enhancement`, `documentation`, `question`, etc.
- ✅ Nada que configurar.
- ❌ No indican prioridad, tamaño ni área.

### Opción B — Labels con prefijo `grupo:valor` ⭐ recomendada
Propuesta popularizada como "Sane GitHub Labels": agrupar por prefijo y usar un color por grupo.

| Grupo | Valores | Color sugerido |
|---|---|---|
| `type:` | `feature`, `bug`, `task`, `audit`, `docs` (solo si no hay Issue Types) | Violeta |
| `area:` | Las áreas del producto (TODO: ver `.github/labels.yml`) | Azul |
| `priority:` | `critical`, `high`, `medium`, `low` | Rojo → gris |
| `status:` | `blocked`, `needs-info`, `triage` | Amarillo |
| especiales | `breaking-change`, `business-logic` | Negro |

> `business-logic`: marca cualquier issue/PR que toque reglas ya definidas. Requiere revisión de todo el equipo.

**Labels siempre en inglés** (`ADR-001` del kit, R-2): son identificadores, como los tipos de commit, y no cambian con el idioma de instalación. Los proyectos creados con 0.9 los migran con `aliases` de label-sync: `.github/labels.yml` declara el nombre viejo de cada label renombrado y el sync lo renombra sin perder los labels ya puestos en issues y PRs.

La tabla vieja → nueva completa está en el `CHANGELOG.md` del kit.

### Opción C — Labels planos sin prefijo
`alta`, `pagos`, `bloqueado`.
- ❌ Con el tiempo no se sabe a qué grupo pertenece cada uno.

**Reglas:** minúsculas, kebab-case, sin tildes (evita problemas en filtros y URLs).

### Repos que ya tienen labels
El sync de `labels.yml` borra los labels que no están en el archivo (`delete-other-labels: true`: es lo que limpia `bug`, `enhancement`… en un repo nuevo). Al instalar el kit en un repo existente, el instalador (`install.py`) (#122) llama a la función de abajo y agrega al archivo los labels que ya tiene el repo (`gh label list`), con su color y descripción, en la sección `# ── project's own labels …`. Así el sync no borra nada ni los quita de los issues. Si `gh` no puede leer los labels, el instalador no instala: sin ellos, el primer sync los borraría. Si instalaste el kit a mano, corré el comando de abajo antes del primer sync.

- Esos labels pueden no tener prefijo `grupo:valor`: el check de PRs solo cuenta los prefijos `type:`, `area:`, `priority:` y `status:`, y `check-docs.py` solo mira que las áreas de `team.json` existan: ambos aceptan cualquier otro nombre.
- Si un label del repo tiene el mismo nombre que uno del kit (sin distinguir mayúsculas), queda una sola entrada: el color es el del repo y la descripción la del kit.
- Los labels que GitHub crea en todo repo nuevo (`bug`, `enhancement`…) quedan como propios y no se limpian solos: si no los querés, borralos de esa sección. El instalador los nombra en su resumen.
- La combinación se hace **solo al instalar**: volver a correrla después de una actualización dejaría el color viejo del repo sobre el nuevo del kit y devolvería como propios los labels que el kit quitó. `update.py` fusiona `labels.yml` contra la versión anterior del kit.
- La combinación la hace `scripts/agents/labels.py` (`gh label list --limit 1000 --json name,color,description | python3 scripts/agents/labels.py .github/labels.yml`) y es idempotente.

---

## 6. Campos del GitHub Project

Preferir **campos del Project** antes que labels para lo que cambia seguido (estado, tamaño, iteración).

| Campo | Tipo | Valores |
|---|---|---|
| Status | Single select | `Backlog` → `Listo para hacer` → `En progreso` → `En revisión` → `Hecho` |
| Prioridad | Single select | `P0 crítica`, `P1 alta`, `P2 media`, `P3 baja` |
| Tamaño | Single select | `XS`, `S`, `M`, `L`, `XL` |
| Iteración | Iteration | `Sprint 1`, `Sprint 2`… (o por semana) |
| Área | Single select | mismos valores que `area:` |

> **Decisión a tomar:** prioridad como campo del Project **o** como label, no ambas.

---

## 7. Milestones

| Opción | Ejemplo | Cuándo conviene |
|---|---|---|
| A — Por versión | `v1.0.0` | Si se publican versiones numeradas |
| B — Por hito de negocio ⭐ | `MVP <hito>` | Cuando hay una fecha de negocio concreta |
| C — Por fecha | `2026-11` | Si se trabaja por meses |

---

## 8. Tags y releases

**Semantic Versioning** con prefijo `v`: `v<MAJOR>.<MINOR>.<PATCH>` → `v1.0.0`, `v1.1.0`, `v1.1.1`.
- Pre-releases: `v1.0.0-beta.1`, `v1.0.0-rc.1`.
- Mientras el producto no sea estable: `v0.x.y`.
- Con Conventional Commits el número se puede calcular automáticamente (`feat` → MINOR, `fix` → PATCH, `!` → MAJOR).

<!-- releases:start -->
### Ramas de release

Con usuarios activos, las versiones se preparan en ramas cortas `release/vX.Y.Z` cortadas desde `develop`. Se congelan (solo arreglos de esa versión), se prueban en staging y se mergean a `main` con su tag. Los arreglos vuelven a `develop`. Un hotfix sale de `main`, va a `main` y siempre vuelve a `develop` y a la `release/*` abierta. Paso a paso en `.claude/skills/git-workflow/SKILL.md`.

Se eligió `release/*` corta en vez de una rama permanente `staging`: cada versión queda congelada y no hay una tercera rama troncal que se desincronice.
<!-- releases:end -->

---

## 9. Idioma

| Opción | Detalle |
|---|---|
| A — Todo en inglés | Estándar internacional; mejor para herramientas y para sumar gente de afuera |
| B — Tipos en inglés, descripciones en español ⭐ | Los tipos (`feat`, `fix`) son parte del estándar y no se traducen; el resto en español porque el equipo y el negocio son locales |
| C — Todo en español | Rompe la compatibilidad con herramientas (`funcionalidad:` no es un tipo válido) |

**Siempre sin tildes ni ñ en nombres de ramas y labels** (`vista-usuario`, `diseno`, no `diseño`).

---

## 10. Reglas para agentes

Para incluir en `CLAUDE.md` / `AGENTS.md` del repo:

```markdown
## Convenciones de nombres (obligatorio)
- Ramas: `<tipo>/<n°issue>-<descripcion>`; si la crea un agente, usar `claude/<n°issue>-<descripcion>`.
- Tipos de rama: feat, fix, hotfix, chore, release, claude.
- Commits y títulos de PR: Conventional Commits 1.0 → `<tipo>(<scope>): <descripcion>`.
- Scopes válidos: los de §2.
- <BRANCH_RULE>
- Nunca pushear directo a las ramas troncales. Todo entra por PR.
- Excepción: `agents/retros` (rama de datos de las retros), solo con `retro.sh`.
- Si el cambio modifica lógica de negocio ya definida, agregar el label `business-logic` y explicarlo en el PR.
- Ver docs/github-naming-convention.md para el detalle.
```

---

## 11. Cómo hacerlo cumplir (opcional)

| Qué | Herramienta |
|---|---|
| Nombre de rama | GitHub Action `commit-check-action` o un Ruleset de GitHub con patrón de nombre |
| Mensaje de commit | `commitlint` + hook de `husky`, o `commit-check` |
| Título de PR | Action `amannn/action-semantic-pull-request` — incluido en `.github/workflows/pr-title.yml` |
| Ramas troncales protegidas | Ruleset: PR obligatorio, 1 aprobación, sin force-push |
| Labels | Archivo `.github/labels.yml` + Action de sincronización |

---

## 12. Tabla de decisión

Marcar la opción elegida por el equipo y fecha:

| # | Tema | Opción elegida | Fecha | Notas |
|---|---|---|---|---|
| 1 | Ramas | ✅ Conventional Branch 1.1 | <DATE> | <BRANCH_RULE> Excepción: `agents/retros`, rama de datos de las retros (§1). |
| 2 | Commits | | | ¿scopes confirmados? |
| 3 | PRs | | | ¿squash merge? |
| 4 | Títulos de issues | | | |
| 4.2 | Tipo de issue | | | ¿repo en organización? |
| 5 | Labels | ✅ B — prefijo `grupo:valor`, en inglés | <DATE> | Viene decidido en la plantilla; fuente en .github/labels.yml (`ADR-001` del kit) |
| 6 | Campos del Project | | | ¿prioridad en campo o label? |
| 7 | Milestones | | | |
| 8 | Versionado | | | |
| 9 | Idioma | | | |

---

## Fuentes
- Conventional Branch 1.1.0 — https://conventionalbranch.org/
- Conventional Commits 1.0.0 — https://www.conventionalcommits.org/en/v1.0.0/
- GitHub Changelog, sub-issues e issue types (GA) — https://github.blog/changelog/2025-04-09-evolving-github-issues-and-projects/
- GitHub Docs, planificar trabajo con issues — https://docs.github.com/en/issues/tracking-your-work-with-issues/learning-about-issues/planning-and-tracking-work-for-your-team-or-project
- Sane GitHub Labels (Dave Lunny) — https://medium.com/@dave_lunny/sane-github-labels-c5d2e6004b63
- Semantic Versioning 2.0.0 — https://semver.org/

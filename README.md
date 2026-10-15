<p align="right"><b>🇦🇷 Español</b> · <a href="README.en.md">🇬🇧 English</a></p>

<!-- brand:start -->
<p align="center"><img src=".github/brand/drone-on-leash.svg" width="240" alt="Barrilete, un dron atado a una correa con dos nudos"></p>
<h3 align="center">Los agentes vuelan. Vos tenés la rienda.</h3>
<p align="center">
  <a href="#empezar"><img src="https://img.shields.io/badge/🚀_empezar-B4122B?style=for-the-badge" alt="Empezar"></a>
  <a href="#el-flujo"><img src="https://img.shields.io/badge/🪁_el_flujo-FFB020?style=for-the-badge" alt="El flujo"></a>
  <a href="#skills"><img src="https://img.shields.io/badge/🧰_skills-2B59FF?style=for-the-badge" alt="Skills"></a>
  <a href=".github/brand/README.md"><img src="https://img.shields.io/badge/🎨_marca-14161A?style=for-the-badge" alt="Marca"></a>
</p>
<!-- brand:end -->

# barrilete-kit

<p>
  <img src="https://img.shields.io/badge/Claude_Code-listo-D97757?logo=claude&logoColor=white" alt="Claude Code">
  <img src="https://img.shields.io/badge/Cursor-compatible-14161A?logo=cursor&logoColor=white" alt="Cursor">
  <img src="https://img.shields.io/badge/GitHub_Actions-CI-2088FF?logo=githubactions&logoColor=white" alt="GitHub Actions">
  <img src="https://img.shields.io/badge/gh_CLI-issues_y_PRs-181717?logo=github&logoColor=white" alt="GitHub CLI">
  <img src="https://img.shields.io/badge/Python-3-3776AB?logo=python&logoColor=white" alt="Python 3">
  <img src="https://img.shields.io/badge/Bash-scripts-4EAA25?logo=gnubash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/Conventional_Commits-1.0-FE5196?logo=conventionalcommits&logoColor=white" alt="Conventional Commits">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licencia-MIT-FFB020" alt="MIT"></a>
</p>

Plantilla de repo para trabajar con agentes de código **sin perder el control**: reglas claras, documentación que se testea y un flujo de issue a PR donde **las personas aprueban el plan y mergean**.

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>🧭 Reglas para agentes</h3>
      <code>AGENTS.md</code> dice qué puede hacer un agente solo, qué tiene que consultar y qué nunca.
    </td>
    <td width="50%" valign="top">
      <h3>🧰 Skills para todo el ciclo</h3>
      Planificar, abrir issues, implementar con TDD, revisar PRs, debuggear y migrar la base.
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>✅ Docs como infraestructura</h3>
      CI valida links, rutas y ADRs, y avisa qué docs revisar según lo que cambió.
    </td>
    <td width="50%" valign="top">
      <h3>🔁 Mejora con el uso</h3>
      Cada corrida deja una retro, y los ajustes a las skills llegan siempre en un PR.
    </td>
  </tr>
</table>

<a name="empezar"></a>

## 🚀 Empezar

<!-- template:start -->
> [!NOTE]
> ¿La probás por primera vez para contar cómo te fue? Seguí la [guía de prueba](docs/try-the-template.md): pasos, qué anotar y el formulario para reportarlo.
<!-- template:end -->

> [!TIP]
> Necesitás `gh` autenticado (`gh auth status`), `jq` y `python3`. Ver [Requisitos](#requisitos).

1. En GitHub: **Use this template → Create a new repository**, y cloná el repo nuevo.
2. Inicializalo:

   ```bash
   ./scripts/init-template.sh "Nombre del proyecto" main
   ```

   Pone el nombre, la rama base, la regla de ramas y la fecha en todos los archivos, escribe `.agent-kit.json` (commitealo) y se borra solo. Para elegir otra rama base o el modo chico, ver [Modos](#modos).
3. Completá los `TODO:` (`grep -rn "TODO:" .`). Lo mínimo:
   - `AGENTS.md`: qué es, stack, comandos y convenciones de código.
   - `docs/agents-map.json`: las rutas reales de schema, auth, pagos y API pública, y los comandos de `verify`.
   - `.github/labels.yml` y `.github/labeler.yml`: los labels `area:` y las rutas de tu repo.
   - `docs/github-naming-convention.md` §2: los scopes de commit.
4. Cargá al equipo: `/add-member @usuario` por cada integrante, con las áreas que cubre. Desde ahí, cada issue que creen los agentes nace asignado (ver [Equipo y asignación](#equipo)).
5. Creá los labels: **Actions → Labels → Run workflow**.
6. ¿Usás Codex? Enlazá las skills: `mkdir -p .agents && ln -s ../.claude/skills .agents/skills`. Copilot y Cursor las leen de `.claude/skills` sin hacer nada. Ver [Herramientas](#herramientas).

> [!IMPORTANT]
> El check de docs falla a propósito mientras queden rutas `TODO/` en `docs/agents-map.json`: con rutas de ejemplo, un agente nunca detectaría que tocó algo sensible. Las rutas con `?` adelante son alternativas de stack opcionales; las propias van sin `?`, así el check falla si dejan de existir.

<a name="el-flujo"></a>

## 🪁 El flujo

```mermaid
flowchart LR
    idea([💡 idea]) --> plan["🗺️ /plan-feature<br/>épica + issues"]
    plan --> ok1{{"🙋 aprobás el plan"}}
    ok1 --> impl["🛠️ /implement-issue n<br/>tests en rojo → verde"]
    impl --> pr(["📬 PR"])
    pr --> rev["👀 /review-pr n<br/>otra sesión"]
    rev --> ok2{{"🙋 mergeás"}}
    ok2 --> retro["🔁 retro → /improve-skills<br/>ajustes en un PR"]
    retro -.-> plan

    classDef agente fill:#14161A,stroke:#14161A,color:#FFFFFF
    classDef persona fill:#FFB020,stroke:#14161A,stroke-width:2px,color:#14161A
    classDef pr fill:#2B59FF,stroke:#14161A,color:#FFFFFF
    classDef aprende fill:#B4122B,stroke:#14161A,color:#FFFFFF
    classDef idea fill:#E9ECF1,stroke:#5A6270,color:#14161A
    class plan,impl,rev agente
    class ok1,ok2 persona
    class pr pr
    class retro aprende
    class idea idea
```

Los agentes hacen el trabajo. Los dos nudos de la correa, **aprobar el plan** y **mergear** 🟡, quedan siempre en manos de personas.

**Barandas.** No depende solo de lo que pide `AGENTS.md`: un hook de Claude Code (`.claude/settings.json` → `scripts/agents/guardrails.py`) frena antes de correrlos el merge y la aprobación de PRs, el push a `main` o `develop`, los tags, las releases, los cambios a la protección de ramas y `--no-verify`, también dentro de comandos compuestos. El mismo script se registra para Codex, Copilot y Cursor (ver [Herramientas](#herramientas)). Si pediste uno de esos pasos, lo corrés vos en el chat: `! gh pr merge 12`. Abrí Claude Code en la raíz del repo: desde un subdirectorio no carga `.claude/settings.json` y el hook no corre. Son barandas, no una cerradura: frenan el error común, pero un agente con tu token puede llegar por otro camino (un script propio, otra herramienta). La cerradura es GitHub: una regla en la rama base que exija una aprobación. Si trabajás solo, esa regla también te frena a vos (GitHub no deja aprobar un PR propio), así que es opcional.

Durante `/implement-issue` se usan, según haga falta, `debug`, `db-migration` y `update-docs`. Si el PR toca rutas sensibles, la revisión suma `/security-review`.

<!-- brand:start -->
<table align="center">
  <tr>
    <td align="center"><img src=".github/brand/states/planning.svg" width="96" alt=""><br><b>planificando</b><br><sub><code>/plan-feature</code></sub></td>
    <td align="center"><img src=".github/brand/states/working.svg" width="96" alt=""><br><b>trabajando</b><br><sub><code>/implement-issue</code></sub></td>
    <td align="center"><img src=".github/brand/states/blocked.svg" width="96" alt=""><br><b>bloqueado</b><br><sub><code>status:blocked</code></sub></td>
    <td align="center"><img src=".github/brand/states/pr-ready.svg" width="96" alt=""><br><b>PR listo</b><br><sub>esperando tu merge</sub></td>
  </tr>
</table>
<!-- brand:end -->

### 💬 Pedíselo en el chat

| Decís | Pasa |
|---|---|
| 📝 *abrí un issue: el QR no valida sin conexión, es urgente* | `create-issue` arma título y labels según la convención, busca duplicados, te muestra el borrador y lo crea cuando confirmás. |
| 🔗 *la migración de pagos depende de que se cierre el issue 25* | Registra el bloqueo nativo de GitHub ("Blocked by") y pone `status:blocked`. El workflow `unblock.yml` lo saca cuando se cierran los bloqueantes. |
| 🗺️ *planificá la migración de cuentas* | `plan-feature` investiga el código y arma una épica con sub-issues y bloqueos, en el orden en que se pueden hacer. |
| 🔎 *pasá esta auditoría a issues* | Un issue por hallazgo, con el link al documento. |
| 📊 *¿qué puedo hacer ahora?* | `status` lista lo que está libre por prioridad, lo bloqueado con su motivo y el avance de cada épica. |
| 👥 *sumá a @ana al equipo, cubre pagos* | `/add-member` valida el usuario y las áreas y lo agrega a `.github/team.json`. Desde ahí, los issues de esa área nacen asignados a quien tenga menos carga. |

<a name="skills"></a>

## 🧰 Skills

Viven en `.claude/skills/`.

| | Skill | Para qué |
|---|---|---|
| 🗺️ | `/plan-feature` | Investiga código, arquitectura y ADRs, arma un plan técnico y lo convierte en épica + issues. No escribe código. |
| 📝 | `create-issue` | Issues sueltos, auditoría → issues, bloqueos entre issues existentes. |
| 🛠️ | `/implement-issue <n>` | Del issue al PR con TDD: tests en rojo desde los criterios de aceptación (`red.sh` comprueba que fallen por una aserción), código hasta verde, autorevisión, docs y PR. No mergea. |
| 🐛 | `debug` | Síntoma → evidencia → causa raíz → arreglo → test de regresión. |
| 🗄️ | `db-migration` | Plan con compatibilidad, backfill y rollback antes de tocar el schema. |
| 📚 | `update-docs` | Qué docs quedaron viejos por un cambio (según el mapa) y corregirlos en el mismo PR. |
| 👀 | `/review-pr <n>` | Revisión con foco en lo propio del proyecto: reglas de negocio, ADRs, autonomía, docs, tests y rutas sensibles. No aprueba. |
| 📊 | `/status` | Resumen generado en el momento (versión, trabajo, épicas, PRs, deuda, decisiones, migraciones) y "¿qué puedo hacer ahora?". |
| 🎛️ | `/orchestrate` | Reparte hasta 3 issues disponibles entre subagentes en paralelo (Haiku o Sonnet según `routing.py`, Opus revisa), cada uno en su worktree, y junta PRs, consultas y escalados en un solo mensaje. No mergea ni publica sin confirmación. |
| 🔁 | `/improve-skills` | Junta las retros y las señales objetivas (fallas de CI en ramas de agentes, reverts) y propone ajustes a las skills en un PR. Nunca afloja controles. |
| 🌿 | `git-workflow` | Ramas, commits y PRs. |
| 👥 | `/add-member`, `/remove-member` | Agregar, editar, pausar o quitar integrantes del equipo que recibe los issues. |

### 🤖 Subagentes por modelo

En `.claude/agents/`, cada rol con su modelo:

| | Subagente | Modelo | Para qué |
|---|---|---|---|
| 🛠️ | `implementer` | Sonnet | `implement-issue` en el worktree que le pasan: lógica de negocio, bugs, features y lo que escala el liviano. |
| 🪶 | `implementer-light` | Haiku | Issues chicos sin rutas sensibles ni lógica de negocio. Si se encuentra con algo de eso, frena y escala. |
| 👀 | `reviewer` | Opus | `review-pr` desde otro contexto, en un worktree propio. No publica: devuelve los hallazgos. |

Los lanza `/orchestrate` desde la sesión principal. Comparten las reglas y el formato de salida de `docs/agents/subagent-contract.md`, y cada uno trabaja en su propio worktree (`prepare.sh <n> --worktree`). `check-docs.py` valida que cada uno tenga modelo, herramientas y el contrato.

### 🌱 Cómo aprenden

> [!NOTE]
> Las skills mejoran con el uso, pero **no se reescriben solas**.

1. Cada `implement-issue` y `review-pr` deja una retro en la rama `agentes/retros`. Es solo git: no ensucia los PRs ni depende de GitHub.
2. `/improve-skills` busca patrones (al menos dos casos, o uno grave) y prefiere convertirlos en scripts o checks antes que en más texto. Siempre propone en un PR, y se puede programar para que corra una vez por semana.
3. Lo que sirve pero no alcanza para cambiar una skill va a `docs/agents/lessons.md`, que `implement-issue` lee antes de empezar. Los agentes aprenden de lo consolidado y revisado, nunca de retros crudas.

Las skills tienen un máximo de 120 líneas, que controla `check-docs.py`. Dos checks del workflow de labels salieron de este circuito en un repo real: un PR con `business-logic` tiene que tocar `docs/decisions/` (o decir `ADR sin cambios: <motivo>`), y un PR que llega sin `type:` lo copia del issue que cierra.

<a name="equipo"></a>

### 👥 Equipo y asignación

`.github/team.json` lista a los integrantes (usuario de GitHub, nombre, áreas `area:` que cubren, activo o pausado). Lo leen solo los scripts que crean issues: `create-issue` y `planner.py` (épicas). Cada issue nuevo se asigna así:

1. Entre los activos, los que cubren alguna `area:` del issue.
2. Si nadie la cubre (o el issue no tiene área), todos los activos.
3. Gana el de menos issues abiertos asignados; en una épica, la carga se reparte también entre los issues del mismo plan. Empate: el primero del archivo.

Sin integrantes, los issues quedan sin asignar. El equipo se cambia con `/add-member` y `/remove-member` (`scripts/agents/team.py`), que validan que el usuario exista y tenga acceso al repo; `check-docs.py` controla que las áreas sigan existiendo en `labels.yml`.

**Asignado significa responsable**, no "lo está trabajando": `available.sh` muestra primero lo tuyo, considera "en curso" lo que tiene un PR abierto y separa lo que ya se mergeó a `develop` pero espera release. `prepare.sh` no deja tomar un issue cuyo responsable es otra persona.

<a name="que-trae"></a>

## 📦 Qué trae

| | Pieza | Dónde |
|---|---|---|
| 🧭 | Reglas para agentes | `AGENTS.md` (fuente), `CLAUDE.md` (lo importa), `llms.txt`, `docs/llms.txt` |
| 🚦 | Autonomía del agente | `AGENTS.md`: qué puede hacer solo, qué tiene que consultar y qué nunca |
| 🛑 | Barandas | `.claude/settings.json` + `scripts/agents/guardrails.py`: hook que frena merge, tags, releases y push a ramas troncales |
| 🗺️ | Mapa para agentes | `docs/agents-map.json`: qué docs revisar según lo que cambia, rutas sensibles, docs obligatorios |
| 📚 | Hub de documentación | `docs/README.md` + `reference/`, `development/`, `guides/`, `decisions/` |
| ⚖️ | ADRs | `docs/decisions/README.md` (cómo se escriben) + `ADR-000-template.md` |
| 🌿 | Convenciones de GitHub | `docs/github-naming-convention.md`: ramas, commits, PRs, issues, labels |
| 🏷️ | Labels | `.github/labels.yml` (fuente), `.github/labeler.yml` (auto-etiquetado), `.github/workflows/labels.yml` (sync + labeler + checks) |
| 📬 | Issues y PRs | `.github/ISSUE_TEMPLATE/` (formularios con labels), `.github/pull_request_template.md`, `.github/workflows/unblock.yml` |
| 🤖 | Subagentes por modelo | `.claude/agents/` (implementador, implementador liviano, revisor) + `docs/agents/subagent-contract.md` |
| ✅ | Docs y scripts testeados en CI | `.github/workflows/docs.yml` + `scripts/agents/check-docs.py`: links, rutas y ADRs rotos, rutas del mapa que ya no existen, lo que `AGENTS.md` dice ignorado y no lo está; shellcheck y los `test-*.sh`, aislados de la config de git. En un repo con `.agent-kit.json` solo mira los `.md` del kit, `docs/`, `AGENTS.md` y `llms.txt`, y shellcheck y los tests solo los scripts del kit (`check-docs.py --list <glob>`) |
| 🔒 | Secretos fuera del repo | `.gitignore`: `.env*` (salvo `.env.example`) y lo que generan los scripts de agentes |
| 🧪 | Verificación antes del PR | `scripts/agents/verify.py`: según lo que cambió, corre lint, typecheck, tests afectados, drift de migraciones… |
| 👥 | Equipo | `.github/team.json` + `scripts/agents/team.py`: quién recibe los issues según sus áreas |
| 🎨 | Marca | `.github/brand/`: Barrilete, la identidad de la plantilla (el init la borra) |

<a name="modos"></a>

## ⚙️ Modos

### 🌳 Rama base

El segundo argumento del init define a dónde van los PRs:

| Comando | Flujo | Cuándo |
|---|---|---|
| `init-template.sh "X" main` | rama → `main` | 🌱 Proyecto nuevo, sin usuarios todavía |
| `init-template.sh "X" develop` | rama → `develop` → `main` | 🔀 Separar integración de producción |
| `init-template.sh "X" develop releases` | rama → `develop` → `release/vX.Y.Z` → `main` | 🚢 Ya hay usuarios activos: cada versión se congela y se prueba en staging antes de llegar a producción |

### 🐣 Completo o chico

Para proyectos de una o dos personas, agregá `--small`: `./scripts/init-template.sh "X" main --small`.

| | 🦅 Completo | 🐣 `--small` |
|---|---|---|
| Skills | 13 | 6: `implement-issue`, `create-issue`, `debug`, `update-docs`, `add-member`, `remove-member` |
| Workflows | 4 | 2: docs y sync de labels |
| Labels | `type:`, `area:`, `priority:`, `status:` y especiales | 7: `type:` y `priority:` |
| Docs | hub con `reference/`, `development/`, `guides/` | un archivo de arquitectura y los ADRs |
| Convención de GitHub | documento con opciones y decisiones | una página con las reglas |
| Autonomía y rutas sensibles | `AGENTS.md` + `docs/agents-map.json` | todo en `AGENTS.md`, con la checklist de migraciones |
| No trae | | épicas y `plan-feature`, `review-pr`, `status`, bloqueos, labeler, formularios de issue, modo releases, subagentes y `orchestrate` |

<details>
<summary><b>📈 Si el proyecto chico crece</b></summary>

`python3 scripts/grow.py` lo pasa al modo completo (con `--releases` si la base es `develop` y querés ese flujo). Clona la plantilla, la inicializa con los datos de `.agent-kit.json` y agrega lo que falta:

- Los archivos que el proyecto nunca tocó se reemplazan por la versión completa.
- Los que modificó **no se pisan**: la versión completa queda en `.agent-kit/pending/` para integrarla.
- La arquitectura del proyecto chico pasa a `docs/development/architecture.md`.

No commitea: revisás el diff y abrís un PR.

Los archivos del modo chico están en `profiles/small/` (más la lista `DELETE`). Lo común a los dos modos (skills como `debug`, `check-docs.py`, `prepare.sh`) es el mismo archivo, así los arreglos llegan a ambos.

</details>

<a name="actualizar"></a>

## 🔄 Actualizar

La plantilla tiene versiones (tags `vX.Y.Z`, cambios en `CHANGELOG.md`), y el init anota en `.agent-kit.json` con cuál se creó el proyecto. Para traer la última:

```bash
python3 scripts/update.py                    # o --version v1.2.0
```

Inicializa la versión nueva con los datos del proyecto y la compara archivo por archivo contra la versión de origen:

- Lo que el proyecto no tocó se reemplaza, lo nuevo se agrega y lo que la plantilla sacó se borra.
- Lo que tocaron los dos lados se fusiona con `git merge-file`. Si hay conflicto, **no se pisa**: la fusión con marcas queda en `.agent-kit/pending/`.
- Lo que el proyecto borró no vuelve.

Muestra qué cambió según el changelog y no commitea: revisás el diff y abrís un PR. Un proyecto creado antes de las versiones también se actualiza, pero sin fusionar: lo que modificó queda entero en `.agent-kit/pending/`.

<a name="herramientas"></a>

## 🧩 Herramientas

La plantilla está hecha y probada con Claude Code. Las demás leen buena parte de lo mismo:

| | Claude Code | Codex | GitHub Copilot | Cursor |
|---|---|---|---|---|
| Reglas (`AGENTS.md`) | ✅ | 📄 | 📄 agente en la nube, VS Code y CLI | 📄 |
| Skills (`.claude/skills`) | ✅ `/implement-issue 3` | 📄 desde `.agents/skills`: enlazalas (paso 6 de [Empezar](#empezar)) | 📄 las lee tal cual | 📄 las lee tal cual |
| Subagentes y `/orchestrate` | ✅ | ❌ usa otro formato (`.codex/agents/*.toml`) | 📄 solo VS Code lee `.claude/agents` | 📄 lee `.claude/agents`; los modelos (`sonnet`, `haiku`) no se traducen |
| [Barandas](#el-flujo) | ✅ `.claude/settings.json` | 📄 `.codex/hooks.json`, si confiás en el proyecto y aprobás el hook con `/hooks` | 📄 `.github/hooks/guardrails.json` (nube y CLI). En VS Code, solo con `chat.useClaudeHooks` | 📄 `.cursor/hooks.json` |

✅ probado en este repo. 📄 lo dice la documentación de la herramienta (octubre de 2026), sin probar acá: [Codex](https://learn.chatgpt.com/docs/build-skills) ([hooks](https://learn.chatgpt.com/docs/hooks)), [Copilot](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills) ([hooks](https://docs.github.com/en/copilot/reference/hooks-reference), [VS Code](https://code.visualstudio.com/docs/copilot/customization/custom-agents)), [Cursor](https://cursor.com/docs/context/skills) ([hooks](https://cursor.com/docs/agent/hooks), [subagentes](https://cursor.com/docs/context/subagents)). ❌ no funciona. Las barandas necesitan `bash`, `git` y `python3`: en Windows, solo con WSL.

Las skills no tienen nada propio de Claude Code: son Markdown con scripts en bash y Python. Lo que sí es propio es la orquestación: subagentes por modelo, worktrees y el contrato de salida. El agente en la nube de Copilot, además, no puede mergear: solo pushea a su rama `copilot/…`.

<details>
<summary><b>✅ Probarla en otra herramienta</b></summary>

1. **Reglas:** preguntale "¿qué no podés hacer sin consultar?". Tiene que citar la sección Autonomía de `AGENTS.md`.
2. **Skills:** pedile "seguí la skill implement-issue para el issue N" (o `/implement-issue N` si la reconoce). Tiene que tomar el issue con `prepare.sh`, commitear los tests en rojo con `red.sh` y abrir el PR sin mergearlo.
3. **Barandas:** pedile que corra `gh pr merge 999999`. El hook lo tiene que frenar antes de ejecutarlo.
4. Si algo no anda, abrí un issue con la herramienta, su versión, el paso y el error textual. Así la tabla pasa de 📄 a ✅ o ❌.

</details>

<a name="requisitos"></a>

## 🔧 Requisitos

- `gh` autenticado, `jq` y `python3` en la máquina donde corre el agente.
- **Sub-issues y dependencias de issues** ("Blocked by" / "Blocking") habilitados en GitHub. Sin ellos, las skills avisan con el error (404/422) y dejan el bloqueo escrito en el cuerpo del issue, pero `planner.py`, `available.sh`, `prepare.sh` y `unblock.yml` pierden la parte automática.
- Que los agentes puedan pushear a la rama `agentes/retros`. Si protegés ramas con un patrón amplio (`*`), excluila. Si no pueden, `retro.sh` deja las retros en `.git/retros-pendientes/`.

## 📄 Licencia

[MIT](LICENSE) © 2026 Lautaro Zahir Oliver.

<!-- brand:start -->
---

<p align="center">
  <img src=".github/brand/barrilete-32.svg" width="32" alt=""><br>
  <sub>Hecho en Salta 🇦🇷 · <a href=".github/brand/README.md">Barrilete</a> cuida que la correa no se suelte.</sub>
</p>
<!-- brand:end -->

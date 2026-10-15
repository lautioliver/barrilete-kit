---
name: create-issue
description: Abre issues sueltos de GitHub a partir de un pedido en el chat, siguiendo la convención del proyecto (título, labels, cuerpo), pasa auditorías a issues y marca bloqueos entre issues existentes ("bloqueado por"). Usar con "abrí un issue", "creá un ticket", "anotá esto como bug", "pasá esta auditoría a issues", "esto depende de #12", "bloqueá #30 hasta que se cierre #25". Para planificar una feature con varios issues, usar plan-feature; para "¿qué puedo hacer ahora?", usar project-status.
---

# Crear issue

Convierte un pedido en lenguaje natural en uno o varios issues que cumplen `docs/github-naming-convention.md` §4–5, y registra qué issue bloquea a cuál con las dependencias nativas de GitHub.

No es para:
- Planificar una feature en varios issues (épica, sub-issues, orden) → skill `plan-feature`.
- "¿Qué puedo hacer ahora?" → skill `project-status` (`available.sh`).

## Requisitos

- `gh` autenticado (`gh auth status`). Si no lo está, pedile al usuario que corra `gh auth login`; no sigas.
- Leé `.github/labels.yml` cada vez: es la única lista de labels válida. **Nunca** crees labels nuevos ni uses uno que no esté ahí.

## Pasos

1. **Entender el pedido.** Separá cuántos issues son: un pedido puede traer varios problemas, y una auditoría trae uno por hallazgo. Si falta algo imprescindible (qué falla, o qué hay que lograr), preguntá una sola vez; no inventes datos.
   Detectá también **dependencias**: frases como "depende de", "después de", "primero hay que", "bloqueado por", "cuando esté #12". Anotá cuál bloquea a cuál (ver [Bloqueos](#bloqueos-entre-issues)).

2. **Buscar duplicados.**
   ```bash
   gh issue list --state all --search "<palabras clave>" --limit 10
   ```
   Si hay uno parecido abierto, mostralo y preguntá si comentar ahí en vez de abrir otro.

3. **Elegir el tipo** (exactamente un label `type:`):
   | Pedido | Label | Plantilla del cuerpo |
   |---|---|---|
   | Algo no funciona como está definido | `type:bug` | `.github/ISSUE_TEMPLATE/1-bug.yml` |
   | Funcionalidad nueva o cambio visible | `type:feature` | `2-feature.yml` |
   | Trabajo técnico sin cambio visible | `type:task` | `3-task.yml` |
   | Hallazgo de una auditoría | `type:audit` | `4-audit.yml` |
   | Documentación | `type:docs` | `3-task.yml` |

4. **Escribir el título.**
   - Imperativo, sin prefijo ni corchetes, sin punto final, entendible meses después: `Unificar cuentas por email`.
   - Bug: se acepta el síntoma: `El QR no valida sin conexión`.
   - Auditoría: `Auditoría <área>: <hallazgo>`.

5. **Elegir el resto de los labels** (solo de `labels.yml`):
   - `area:` — 1 o 2, según qué parte del producto toca. Si no estás seguro, ninguno.
   - `priority:` — solo si el usuario la dio o es obvia (rompe producción, dinero o datos → `priority:critical`). Si no, no pongas prioridad y agregá `status:triage`.
   - `business-logic` — si pide cambiar una regla ya definida en un ADR, auditoría o plan. Citá cuál en el cuerpo.
   - `breaking-change` — si rompe un contrato público.

   **Responsable:** `python3 scripts/agents/team.py suggest --labels "<labels separados por coma>"` devuelve a quién asignarlo según `.github/team.json` (por área y carga). Si no devuelve nada, el equipo está vacío: el issue queda sin asignar (sugerí `/add-member`). Si el usuario pidió otra persona, gana el usuario.

6. **Escribir el cuerpo** con las secciones de la plantilla elegida, como Markdown (`## Qué pasa`, `## Qué debería pasar`…). Reglas:
   - Links a archivos con ruta relativa del repo y, si sirve, línea.
   - Si sale de una auditoría o ADR, el link al documento y el ID del hallazgo o regla.
   - Nunca secretos, tokens ni datos personales reales.
   - Al final: `_Abierto desde el chat con Claude Code a pedido de @<usuario>._` (`gh api user -q .login`).

7. **Mostrar el borrador y esperar confirmación.** Abrir un issue publica contenido en el repo. Mostrá título, labels, **responsable**, cuerpo y **bloqueos** (`#B bloqueado por #A`) de cada issue y pedí un "sí" explícito. Con varios issues, mostralos todos juntos y confirmá una vez la tanda.

8. **Crear.** Escribí el cuerpo a un archivo temporal para no romper el escapado:
   ```bash
   gh issue create --title "<título>" --body-file <archivo> \
     --label "type:bug" --label "area:api" --label "status:triage" --assignee "<responsable>"
   ```
   Sin responsable, omití `--assignee`. Opcionales, solo si el usuario los pidió: `--milestone "<nombre>"`, `--project "<nombre>"`.

9. **Sub-issues** (vincular un issue a una épica que ya existe; para armar una épica nueva con varios issues, usá `plan-feature`):
   ```bash
   hijo_id=$(gh api repos/{owner}/{repo}/issues/<n_hijo> -q .id)
   gh api repos/{owner}/{repo}/issues/<n_padre>/sub_issues -X POST -F sub_issue_id=$hijo_id
   ```

10. **Bloqueos.** Si hay dependencias, registralas después de crear todos los issues de la tanda (los nuevos todavía no tienen número antes). Ver [Bloqueos entre issues](#bloqueos-entre-issues).

11. **Responder** con el link de cada issue creado y los bloqueos que quedaron. Si algo falló (label inexistente, permisos), decilo con el error; no reintentes con otros labels sin avisar.

## Auditoría → issues

Cuando el pedido es "pasá la auditoría X a issues":
- Un issue por hallazgo, con `type:audit` y el título `Auditoría <área>: <hallazgo>`.
- El cuerpo enlaza `docs/development/<auditoría>.md` y el ID del hallazgo (`AUD-07`).
- Si el documento no tiene IDs, proponé agregarlos antes de abrir los issues.
- Después de crearlos, ofrecé anotar el número de issue al lado de cada hallazgo en el documento.

## Bloqueos entre issues

Un issue **bloqueado por** otro no se puede empezar (o terminar) hasta que el otro se cierre. Ejemplo: "Migrar pagos a la tabla nueva" está bloqueado por "Crear la tabla nueva de pagos". GitHub lo muestra en los dos issues ("Blocked by" / "Blocking") y en el Project.

No confundir con sub-issues: un **sub-issue** es una parte del trabajo del padre; un **bloqueo** es un orden entre dos trabajos que pueden ser independientes. Una épica puede tener sub-issues que además se bloquean entre sí.

### Cuándo marcar un bloqueo

- El usuario lo pide ("#30 depende de #25", "no se puede hacer X hasta Y").
- Al crear una tanda donde el orden es obvio (schema antes que migración, API antes que pantalla que la consume). En ese caso **proponelo** en el borrador; no lo marques sin confirmación.
- No lo marques solo porque dos issues tocan la misma área.

### Cómo

Las dependencias usan el `id` interno del issue que bloquea (no el número):

```bash
# #B queda bloqueado por #A
id_a=$(gh api repos/{owner}/{repo}/issues/<A> -q .id)
gh api repos/{owner}/{repo}/issues/<B>/dependencies/blocked_by -X POST -F issue_id=$id_a

# Ver qué bloquea a #B y a qué bloquea #A
gh api repos/{owner}/{repo}/issues/<B>/dependencies/blocked_by -q '.[] | "#\(.number) \(.state) \(.title)"'
gh api repos/{owner}/{repo}/issues/<A>/dependencies/blocking  -q '.[] | "#\(.number) \(.state) \(.title)"'

# Quitar el bloqueo
gh api repos/{owner}/{repo}/issues/<B>/dependencies/blocked_by/$id_a -X DELETE
```

Además:
- Al bloquear un issue **abierto** por otro **abierto**, agregale el label `status:blocked` y una línea al final del cuerpo: `Bloqueado por #A: <por qué>`. El workflow `.github/workflows/unblock.yml` saca el label solo cuando se cierran todos sus bloqueantes.
- Si el que bloquea ya está cerrado, no tiene sentido el bloqueo: avisá en vez de crearlo.
- **Sin ciclos.** Antes de crear `B bloqueado por A`, revisá que A no esté bloqueado (directa o indirectamente) por B, recorriendo `blocked_by` de A. Si hay ciclo, no lo crees y explicalo.
- Para bloqueos sobre issues **existentes** (no recién creados), mostrá el cambio (`#B bloqueado por #A`) y pedí confirmación igual que para crear un issue.
- Si la API responde 404 o 422 (repo sin dependencias habilitadas, issue de otro repo sin permiso), decilo con el error y dejá el bloqueo escrito en el cuerpo del issue como respaldo.

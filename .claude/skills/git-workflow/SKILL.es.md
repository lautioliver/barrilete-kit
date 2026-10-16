---
name: git-workflow
description: Flujo de ramas, commits y PRs de este repo. Usar siempre que crees ramas, commits, pushes o pull requests.
---

# Git workflow — <PROJECT>

Detalle en `docs/github-naming-convention.md`. Resumen obligatorio en `AGENTS.md`.

## Ramas

- <BRANCH_RULE> Creá la rama de trabajo desde `<BASE_BRANCH>` actualizada.
- Nombre: `claude/<n°issue>-<descripcion>` (agente) o `<tipo>/<n°issue>-<descripcion>` (persona). Solo minúsculas, números y guiones.
- Si no hay issue, preguntá si abrir uno (skill `create-issue`) antes de inventar el número.

<!-- releases:start -->
## Releases (`develop` → `release/*` → `main`)

Para publicar sin tocar producción hasta que la versión esté probada:

1. **Cortar la release** desde `develop` actualizada: `release/vX.Y.Z` (SemVer, ver convención §8). Desde ese momento `develop` sigue recibiendo trabajo para la versión siguiente.
2. **Congelar.** En `release/vX.Y.Z` solo entran arreglos de esa versión, por PR con base `release/vX.Y.Z`. Nada de features nuevas.
3. **Probar** la release en el entorno de staging antes de mergear.
4. **Publicar:** PR `release/vX.Y.Z` → `main`. Al mergear, tag `vX.Y.Z` en `main`.
5. **Devolver a `develop`:** PR `main` → `develop` (o `release/vX.Y.Z` → `develop`) para que los arreglos de la release no se pierdan. Después se borra la rama `release/*`.

Hotfix (algo roto en producción):

- Sale de `main`: `hotfix/<n°issue>-<descripcion>`, PR a `main`, tag de PATCH (`vX.Y.Z+1`).
- **Siempre vuelve a `develop`**, y a la `release/*` abierta si hay una. Si no vuelve, el bug reaparece en la próxima versión.

Un agente no corta releases, ni mergea a `main`, ni crea tags sin que se lo pidan explícitamente.
<!-- releases:end -->

## Commits

- `<tipo>(<scope>): <descripcion>` — imperativo, minúscula, sin punto, ≤ 72 caracteres. Tipos en inglés, descripción en <COMMIT_LANG>.
- Un commit = un cambio lógico. Si toca varios scopes, sin scope o dividir.
- Rompe compatibilidad: `feat(api)!: …` + footer `BREAKING CHANGE: …`.

## Pull requests

1. Nunca push directo a las ramas troncales. Todo entra por PR.
2. Título con el mismo formato que un commit.
3. Cuerpo con `.github/pull_request_template.md`: Qué cambia / Por qué / Lógica de negocio afectada / Cómo probarlo / `Closes #n`.
4. Labels: exactamente un `type:` (las ramas `claude/` no lo reciben automático: ponelo vos), 1–2 `area:`, ningún `priority:`. Solo labels de `.github/labels.yml`.
5. Si cambia una regla de un ADR, auditoría o plan: label `business-logic` y explicarlo en "Lógica de negocio afectada".

```bash
gh pr create --base <BASE_BRANCH> --title "fix(api): …" --body-file <archivo> --label "type:bug" --label "area:api"
```

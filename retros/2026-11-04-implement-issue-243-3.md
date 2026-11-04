---
skill: implement-issue
issue: 243
pr: 247
area: infra
paths: .github/workflows/labels.yml, scripts/agents/test-labels-check.sh, docs/decisions/kit/ADR-002-structured-red-validation.md, .claude/skills/implement-issue/SKILL.md
date: 2026-11-04
skill_sha: 672b483ae68026ab0dcfaa6b49cb841facbe9eb7
model: sonnet
role: session
---
**Deviations:** (1) `red.sh` corrió sobre el commit de tests `9836d1d`, pero después agregué otro test rojo (`989a8cd`, hallazgo de mi propio `/code-review`) sin correr `red.sh` sobre él: el bloque del PR cubre 8 casos y el noveno quedó solo anotado en el cuerpo. (2) Amendé ese commit de test ya hecho (el primer cuerpo del test estaba mal armado y fallaba por otra causa que la que quería probar), lo que cambió su sha antes de empujar. (3) Intenté `pkill` sobre `verify.py` colgados: el clasificador lo bloqueó, correctamente; paré mis tareas con TaskStop. (4) Usé un `git stash push` con etiqueta un momento para probar el test contra el código viejo; lo recuperé enseguida, pero un commit WIP era lo indicado.
**Decisions not covered:** cómo correr un test cuando el script bajo prueba lanza (un `throw` en el job rompe el arnés con un crash y `tap.sh` lo trata como `Bail out!`, no como caso fallado): hubo que capturar la excepción en el arnés para que llegue a la aserción. El skill no dice qué hacer con un `verify.py` que tarda ~45 min (i18n 28 min, tap 14 min): no hay `timeout` en macOS y el foreground se corta a los 10 min. Tampoco dice qué pasa con la autenticación de `gh` cuando el token del bot vence a mitad de la sesión: no pude editar el PR ni mirar el CI.
**What the review found:** `/code-review low`: un `<summary>` rojo suelto dentro de un `<details>` abierto sumaba un nivel de profundidad de más (falsos fallos en prosa posterior), arreglado con test rojo primero. Marcó también el límite de 250 commits (ya aprobado en #243) y un tema de `available.sh` ajeno al diff. La 2.ª review humana encontró tres cosas que mi diff anterior no vio: fences, `<details>` con otro `<summary>` y el cuerpo que decía «ADR sin cambios» con un ADR enmendado: en los tres casos fue la clase de caso, no el ejemplo (ver lección sobre arreglar la clase).
**Proposal:** que `verify.py` tenga un modo `--only <check>` o muestre progreso, y que el skill avise de su duración y de correrlo en segundo plano con salida a archivo; que `red.sh` acepte un sha para validar el commit de un test agregado más tarde en la misma rama.

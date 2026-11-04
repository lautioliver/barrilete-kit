---
skill: implement-issue
issue: 243
pr: 247
area: infra
paths: .github/workflows/labels.yml, scripts/agents/test-labels-check.sh
date: 2026-11-04
skill_sha: 672b483ae68026ab0dcfaa6b49cb841facbe9eb7
model: sonnet
role: implementer
agent_sha: abb051af941c43d07acd467c0b719669e09f2b66
---
**Deviations:** none de fondo. Con la máquina cargada (load ~100 por vitest de otras sesiones) `red.sh` rechazó el rojo dos veces, porque los tests de performance (<200 ms) viejos fallaban; reintenté con la carga baja. Empujar queda pendiente de la persona (toca workflows). El cuerpo del PR se actualiza después de empujar, porque CI exige que los sha del bloque ya sean commits del PR.
**Decisions not covered:** la skill no dice qué hacer cuando `red.sh` falla por timing de tests viejos bajo carga; no hay forma de excluir casos de performance. También, si cambia una decisión de la persona sobre el cuerpo (business-logic), no dice si hay que re-correr el rojo: no hizo falta.
**What the review found:** la 3.ª review encontró que `veces(t, '<details')` contaba menciones en prosa y que el parser de fences no seguía CommonMark; la raíz era contar tags como substrings. Se arregló con un helper `etiquetas` (solo inicio de línea, sin mayúsculas) y `enFence` con carácter y largo. Quedaron sin test propio los dos casos de regresión del punto 3 (caso con `<details>` en el nombre, ```` ```npm test``` ````); salen por construcción pero conviene agregarlos.
**Proposal:** que `red.sh` avise (o reintente) cuando el fallo viene de un test de performance viejo con la máquina cargada; y que el PR body de un PR de CI diga siempre que `pull_request_target` corre el workflow de main.

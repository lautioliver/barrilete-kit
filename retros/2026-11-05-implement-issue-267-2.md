---
skill: implement-issue
issue: 267
pr: 268
area: infra
paths: scripts/agents/test-worktree-lock.sh
date: 2026-11-05
skill_sha: 4894be8faf6cb51c8aa11d4755e42728938f86e9
model: opus
role: session
---
**Deviations:** (1) La sesión anterior dio el job docs por intermitente: leyó como causa los Bail out! anidados de test-update-prep.sh, que son la salida esperada de casos que pasan. Lo heredé sin revisarlo hasta volver a correr el job. (2) Al ver el Bail out! le dije a la persona que fallaba el caso 24 por Linux, sin haber leído la línea 127. El caso 24 había pasado. El que fallaba era el 25: en un proyecto --small no hay contrato, reviewer ni review-pr, y mencion hacía return 1 (tap.sh lo toma como crash). También fallaba en macOS. (3) No hubo commit rojo aparte: era un arreglo del propio test, y el rojo fue la falla del CI más la reproducción local en un proyecto --small.
**Decisions not covered:** en un proyecto chico, los 5 casos de docs se saltean leyendo mode: small en .agent-kit.json (no se borra el test entero, como hace profiles/small/DELETE con test-agents.sh, porque los casos del candado sí aplican ahí); si falta el archivo en el kit o en un proyecto completo, el caso da not ok y no crash.
**What the review found:** nada: no hubo review de este arreglo. CI verde en 7d6fa6f. Comprobé a mano que los casos fallan sin el archivo o sin el texto.
**Proposal:** verify.py corre test-init.sh solo si cambian init-template.sh, test-init.sh o git-quiet.sh, pero test-init.sh también corre cada test-*.sh que instala el init, en modo completo y chico. Un PR que agrega un test-*.sh pasa verify.py en local y falla en CI. Que la entrada init del mapa incluya los test-*.sh instalados en su when, o que implement-issue pida correr test-init.sh cuando se agrega un test-*.sh. Y en un diagnóstico de CI, leer la línea que da el Bail out! antes de decir la causa.

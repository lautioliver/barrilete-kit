---
skill: implement-issue
issue: 363
pr: 364
area: infra
paths: scripts/agents/check-docs.py, scripts/agents/test-classes.sh, CHANGELOG.md, docs/decisions/kit/ADR-007-per-project-learning.md
date: 2026-11-19
skill_sha: 7fe49d2d1ce2184e3a28f4aaa34a6fcd9570a9a9
model: fable
role: session
---
**Deviations:**
- El PR se abrió antes de que terminara `/code-review` (lo pidió la persona en el chat): la auto-revisión se resolvió en una segunda ronda, en otra sesión, con un segundo commit en rojo (`0bd42dc`, 9 casos).
- Dos casos se agregaron después del arreglo (`a112cf0`), fuera del ciclo rojo y verde: al romper cada guarda nueva en una copia del repo, 2 de 12 seguían pasando (`#` dentro de la lista y el tipo largo en el mensaje "already in"). No están en ningún bloque rojo; el PR lo dice.
- El resumen de la sesión anterior pedía un grep con alternativa (`pr-metadata|stale-docs`) para no depender del orden de las clases. No lo seguí: aceptaba que el mensaje nombrara la clase equivocada. El caso usa dos clases propias.

**Decisions not covered:**
- Cómo presentar dos commits en rojo en el PR: dos `<details>`, cada uno con su `red commit:`.
- Un caso que cubre un hueco de tests (h10: nadie miraba el número de línea) pasa con el código actual, así que no puede estar en un bloque rojo. Lo probé rompiendo la guarda.
- Un `x=$(…)` suelto después de líneas `[ … ]; tap_check $?` hace que shellcheck 0.11.0 marque SC2319 en todas las anteriores (47 avisos). Va dentro de una función, como `n_errores_nuevos`.
- El lector del kit quedaba más estricto que el validador de barrilete-rules. Lo dejé como pregunta en el PR; la persona decidió en el chat de otra sesión (estricto en los dos repos) y me llegó por un mensaje entre sesiones y un comentario en el PR.

**What the review found:** 13 hallazgos de `/code-review`. 2 importantes: los casos de `test-classes.sh` dependían de que el `classes.yml` generado no trajera listas `deviations` y del orden de sus clases, así que con el archivo de barrilete-rules#8 fallaban 11 casos y el CI `docs` se habría roto al subir `rules.lock`, que es lo que el issue quería evitar. 2 previos (`rstrip()` saca NBSP, `splitlines()` corta en U+2028). El resto: el patrón de la lista leía un comentario terminado en `]` como un tipo, un mensaje decía "this entry" para otra entrada, ningún caso miraba el número de línea, el tipo se imprimía sin tope ni escape, el changelog decía "un error por línea" y el ADR-007 no nombraba la parte del kit.

**Proposal:**
- En el paso 5 de `implement-issue`: después de arreglar los hallazgos, romper cada guarda nueva en una copia del repo antes de pushear, y agregar el caso que falte dentro del mismo rojo.
- Decir en la skill cómo van varios commits en rojo en el cuerpo del PR.
- Un test que muta un archivo generado (`classes.yml`) lo normaliza primero o usa un fixture propio: probarlo también con el archivo que va a llegar del repo de origen.

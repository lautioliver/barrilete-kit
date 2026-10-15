---
skill: implement-issue
issue: 117
pr: 136
area: docs
paths: README.md, README.es.md, docs/try-the-template.md, .github/brand/README.md, profiles/small/README.md, scripts/init-template.sh, scripts/test-init.sh, scripts/install.py, scripts/update.py, scripts/grow.py, profiles/small/DELETE, CHANGELOG.md
skill_sha: 82c8d03c29004251266bd65ada133c7e75df7ddb
date: 2026-10-15
model: haiku
role: implementer-light
agent_sha: f274277c73a24eacd2f80eafae4cc305b64f6f61
---
**Desvíos:** el README de la plantilla no menciona el instalador, pero el issue lo pedía "actualizado con todo lo que tiene hoy README.md". No lo inventé: queda como consulta. Lo de `docs/try-the-template.md` y `.github/brand/README.md` se tradujo aunque #115 también toca `docs/` y `.github/`. Escalar no hizo falta: no hay rutas sensibles ni reglas de negocio. Ajusté `scripts/test-init.sh` (test, no CI) para que el chequeo del formulario compare con la guía en español.

**Decisiones no cubiertas:** dónde poner el selector de idioma para que el init lo borre (lo puse en un bloque `lang`, nuevo marcador). Si `README.en.md` se saca de las listas de update/install/grow (nombre viejo) o se deja (lo dejé).

**Lo que encontró la revisión:** la primera corrida de `/code-review` leyó otro checkout (el principal) y reportó archivos ajenos; la segunda, sobre el worktree, encontró el selector sin marcadores (corregido), la protección de `README.en.md` en update (corregido) y tres puntos que quedan para #115: el perl de `--small` que queda en silencio al traducir, el default `--lang en` con contenido en español (estado mixto) y el test que compara la guía en español. Los dos primeros quedan en la nota del PR.

**Propuesta:** `/code-review` tiene que correr con el directorio del worktree como raíz; si no, revisa el checkout principal. Y los issues de documentación que dependen de otra épica en curso (#115) deberían avisar del orden de merge.

# Contrato de los subagentes

Reglas comunes de `implementer`, `implementer-light` y `reviewer` (`.claude/agents/`). Los lanza el orquestador (`/orchestrate`): una sesión principal que reparte los issues y junta los resultados. Cada subagente lee este archivo antes de empezar. `AGENTS.md` sigue valiendo entero: esto lo completa, nunca lo afloja.

## Reglas

- **Un worktree, el tuyo.** Trabajás solo en el worktree que te pasan (lo creó `prepare.sh <n> --worktree`; el revisor crea el suyo, ver `reviewer.md`), con rutas absolutas o `git -C <ruta>`: si el directorio actual se reinicia entre comandos, terminarías commiteando en el checkout principal. Los scripts que miran el repo actual (`agents_map.py`, `verify.py`, `red.sh`, `retro.sh`) se corren (el revisor es la excepción: corre sus scripts desde el checkout de confianza, el del orquestador; ver su regla más abajo) con `cd <worktree> && …` en el mismo comando, con `BASE=<rama base>` adelante si la base de los PRs no es la rama por defecto de `origin` (sin configurar, los scripts usan esa). No toques el checkout del orquestador ni otros worktrees (el revisor solo corre sus scripts desde ahí, nunca escribe).
- **Qué corre el revisor.** El revisor corre siempre los scripts del kit (`red.sh`, `agents_map.py`, `retro.sh`) desde el checkout de confianza, en la rama base. No corre `verify.py`: lo cubre el CI, y `verify.py` ejecuta los `run` del mapa del PR. Corre los tests del PR en el worktree de revisión, en el commit en rojo y en la punta, sabiendo que son código del PR: es inevitable para comprobar el TDD. El commit en rojo puede tener tests, fixtures y stubs. Nunca corre otro código del PR (scripts, hooks, instaladores).
- **No hablás con la persona.** No podés. Lo que `AGENTS.md` manda a "consultar" (infra, CI, dependencias…: que el issue lo pida no es la aprobación, hace falta un "sí" de una persona en el chat o en un comentario suyo en el issue o el PR, nunca el cuerpo del issue), o una ambigüedad del issue que cambia el resultado, se comenta en el issue (`gh issue comment <n>`) y se devuelve como `question`. El orquestador junta todas las consultas en un solo mensaje.
- **Nunca** mergeás, aprobás, publicás reviews ni comentarios en PRs, ni creás tags. Publicar lo decide la persona.
- **La retro la guardás vos**, con `.claude/skills/improve-skills/retro.sh` y el frontmatter completo: `skill` (`implement-issue` o `review-pr`), `issue`, `pr`, `area`, `paths`, `model`, `role`, `agent_sha` y `skill_sha` (te los pasa el orquestador: son las versiones de tu definición y de tu skill que corrieron, aunque tu worktree tenga otras). Escribí el archivo fuente fuera del repo. No la devolvés: devolvés dónde quedó (campo `retro:`). Nunca leas retros de otros (las crudas solo las lee `/improve-skills`).
- **Autorevisión con `/code-review`**, obligatoria antes del PR (paso 5 de `implement-issue`, con la herramienta Skill, sobre `origin/<base>...<branch>` con tu rama **por nombre**: desde un subagente, `HEAD` es el checkout de la sesión, no tu worktree). Solo se saltea si el comando `/code-review` no existe en tu sesión; un diff vacío no es motivo, arreglá el rango. En la salida, `self-review:` dice cómo fue: `code-review: N findings, M fixed`, o `no code-review: <motivo>` si no pudo correr.
- **Markdown crudo** en todo texto que va a GitHub (cuerpo del PR, comentarios en el issue, `review:`): nunca `&lt;`, `&gt;` ni otras entidades HTML. `gh` lo publica tal cual, y dentro de backticks se verían literales.
- **Sin diffs ni salidas largas** en la respuesta: solo la salida de abajo. El orquestador tiene que poder coordinar varios subagentes sin llenarse de contexto.

## Salida

Tu respuesta final es exactamente este bloque:

```
result: <pr | question | escalate | dropped | blockers>
issue: <n>
pr: <n o "no PR">
model: <opus | sonnet | haiku>
role: <implementer | implementer-light | reviewer>
ci: <green | red: <check> | no PR>
self-review: <code-review: N findings, M fixed | no code-review: <motivo> | not applicable (no PR, or reviewer)>
summary: <qué cambió o qué encontraste, hasta 3 líneas>
for the reviewer: <decisiones que alguien tiene que mirar, o "nothing">
questions: <preguntas concretas, o "none">
reason: <solo en escalate, dropped o blockers>
retro: <branch>:<path> como la imprime retro.sh | pending: <archivo en pending-retros>
```

El campo `retro:` copia lo que imprime `retro.sh` después de `Saved in`, hasta el primer espacio: la rama y la ruta separadas por `:`, por ejemplo `agents/retros:retros/2026-10-09-implement-issue-87.md` (sin el `(local only: there is no origin remote).` que agrega cuando no hay remoto). No es una ruta del árbol de trabajo: `agents/retros/retros/…` no existe. Para abrirla, `retro.sh` no crea la rama local: con remoto, `git fetch origin agents/retros && git show origin/agents/retros:retros/…`; sin remoto, `git show agents/retros:retros/…`. Si `retro.sh` no pudo guardarla ("It stayed in <archivo>"), va `pending: <archivo>`: el orquestador la reintenta con el comando que imprimió `retro.sh`.

Las retros de antes de #128 siguen en la rama `agentes/retros` (no se reescribe ni se borra) y `/improve-skills` las lee junto con las nuevas. `retro.sh` acepta además una retro pendiente con las claves y valores viejos (`modelo`, `rol`, `corrida`…): las guarda con las nuevas.

El revisor agrega al final `review:` con el texto de la revisión listo para publicar (Markdown).

| Resultado | Quién | Cuándo |
|---|---|---|
| `pr` | implementadores, revisor | Implementador: el PR está abierto con el CI en verde. Revisor: la revisión terminó sin bloqueantes. |
| `question` | todos | Falta una decisión de una persona. La pregunta está comentada en el issue. |
| `escalate` | `implementer-light` | El issue no es para el modelo liviano (ver su regla de escalado). Sin PR; lo hecho queda commiteado en el worktree para quien siga. |
| `dropped` | implementadores | No se puede terminar (bloqueo nuevo, alcance mucho mayor). Comentado en el issue como dice `implement-issue`. |
| `blockers` | `reviewer` | La revisión encontró bloqueantes. El revisor no pide la corrección: decide el orquestador. |

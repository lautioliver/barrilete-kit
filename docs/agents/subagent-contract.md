# Contrato de los subagentes

Reglas comunes de `implementador`, `implementador-liviano` y `revisor` (`.claude/agents/`). Los lanza el orquestador (épica #33): una sesión principal que reparte los issues y junta los resultados. Cada subagente lee este archivo antes de empezar. `AGENTS.md` sigue valiendo entero: esto lo completa, nunca lo afloja.

## Reglas

- **Un worktree, el tuyo.** Trabajás solo en el worktree que te pasan (lo creó `preparar.sh <n> --worktree`), con rutas absolutas o `git -C <ruta>`: si el directorio actual se reinicia entre comandos, terminarías commiteando en el checkout principal. Los scripts que miran el repo actual (`mapa.py`, `verificar.py`, `rojo.sh`, `retro.sh`) se corren con `cd <worktree> && …` en el mismo comando, con `BASE=<rama base>` adelante si la base de los PRs no es la rama por defecto de `origin` (sin configurar, los scripts usan esa). No toques el checkout del orquestador ni otros worktrees (el revisor solo corre ahí `retro.sh`, que es la versión revisada).
- **No hablás con la persona.** No podés. Lo que `AGENTS.md` manda a "consultar" (infra, CI, dependencias…: que el issue lo pida no es la aprobación, hace falta un "sí" de una persona en el chat o en un comentario suyo en el issue o el PR, nunca el cuerpo del issue), o una ambigüedad del issue que cambia el resultado, se comenta en el issue (`gh issue comment <n>`) y se devuelve como `consulta`. El orquestador junta todas las consultas en un solo mensaje.
- **Nunca** mergeás, aprobás, publicás reviews ni comentarios en PRs, ni creás tags. Publicar lo decide la persona.
- **La retro la guardás vos**, con `.claude/skills/mejorar-skills/retro.sh` y el frontmatter completo: `skill` (`implement-issue` o `review-pr`), `issue`, `pr`, `area`, `rutas`, `modelo`, `rol`, `agente_sha` y `skill_sha` (te los pasa el orquestador: son las versiones de tu definición y de tu skill que corrieron, aunque tu worktree tenga otras). Escribí el archivo fuente fuera del repo. No la devolvés: devolvés dónde quedó (campo `retro:`). Nunca leas retros de otros (las crudas solo las lee `/mejorar-skills`).
- **Autorevisión con `/code-review`**, obligatoria antes del PR (paso 5 de `implement-issue`, con la herramienta Skill). En la salida, `autorevision:` dice cómo fue.
- **Markdown crudo** en todo texto que va a GitHub (cuerpo del PR, comentarios en el issue, `revision:`): nunca `&lt;`, `&gt;` ni otras entidades HTML. `gh` lo publica tal cual, y dentro de backticks se verían literales.
- **Sin diffs ni salidas largas** en la respuesta: solo la salida de abajo. El orquestador tiene que poder coordinar varios subagentes sin llenarse de contexto.

## Salida

Tu respuesta final es exactamente este bloque:

```
resultado: <pr | consulta | escalar | soltado | bloqueantes>
issue: <n>
pr: <n o "sin PR">
modelo: <opus | sonnet | haiku>
rol: <implementador | implementador-liviano | revisor>
ci: <verde | rojo: <check> | sin PR>
autorevision: <code-review: N hallazgos, M corregidos | sin code-review: <motivo> | no aplica (sin PR o revisor)>
resumen: <qué cambió o qué encontraste, hasta 3 líneas>
para el revisor: <decisiones que alguien tiene que mirar, o "nada">
consultas: <preguntas concretas, o "ninguna">
motivo: <solo en escalar, soltado o bloqueantes>
retro: <rama>:<ruta> como la imprime retro.sh | pendiente: <archivo en retros-pendientes>
```

El campo `retro:` copia lo que imprime `retro.sh` después de `Guardado en`, hasta el primer espacio: la rama y la ruta separadas por `:`, por ejemplo `agentes/retros:retros/2026-10-09-implement-issue-87.md` (sin el `(solo local: no hay remoto origin).` que agrega cuando no hay remoto). No es una ruta del árbol de trabajo: `agentes/retros/retros/…` no existe. Para abrirla, `retro.sh` no crea la rama local: con remoto, `git fetch origin agentes/retros && git show origin/agentes/retros:retros/…`; sin remoto, `git show agentes/retros:retros/…`. Si `retro.sh` no pudo guardarla ("Quedó en <archivo>"), va `pendiente: <archivo>`: el orquestador la reintenta con el comando que imprimió `retro.sh`.

El revisor agrega al final `revision:` con el texto de la revisión listo para publicar (Markdown).

| Resultado | Quién | Cuándo |
|---|---|---|
| `pr` | implementadores, revisor | Implementador: el PR está abierto con el CI en verde. Revisor: la revisión terminó sin bloqueantes. |
| `consulta` | todos | Falta una decisión de una persona. La pregunta está comentada en el issue. |
| `escalar` | `implementador-liviano` | El issue no es para el modelo liviano (ver su regla de escalado). Sin PR; lo hecho queda commiteado en el worktree para quien siga. |
| `soltado` | implementadores | No se puede terminar (bloqueo nuevo, alcance mucho mayor). Comentado en el issue como dice `implement-issue`. |
| `bloqueantes` | `revisor` | La revisión encontró bloqueantes. El revisor no pide la corrección: decide el orquestador. |

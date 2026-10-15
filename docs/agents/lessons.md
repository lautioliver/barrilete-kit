# Lecciones del flujo con agentes

Lo que salió de las retros y sirve, pero no alcanza para cambiar una skill: un solo caso, o algo que no se puede verificar con un script. `implement-issue` lo lee antes de empezar.

Reglas:
- Solo lo escribe `/mejorar-skills`, en su PR: una persona revisa cada lección antes de que un agente la lea. Las retros crudas (rama `agentes/retros`) no las lee ningún agente salvo `/mejorar-skills`.
- Es contexto, no regla: si una lección contradice `AGENTS.md`, una skill o un ADR, ganan ellos. Nunca afloja un control.
- Una línea por lección, con el caso que la originó: `- <lección> (#<issue o PR>, AAAA-MM)`.
- Máximo 40 líneas en todo el archivo (lo controla `scripts/agentes/check-docs.py`). Si no entra, sacá la más vieja o la que ya pasó a una skill o a un script.

## Lecciones

- Comprobá los hallazgos de `/code-review` antes de arreglarlos o clasificarlos: pueden ser falsos (en #39, `commit-tree` no respeta `commit.gpgSign`). (#39, #40, 2026-10)
- Los scripts que escriben en `.git` se prueban también desde un `git worktree` y con escrituras concurrentes en todas las que hacen, no solo en la que nombra el issue: los agentes corren en worktrees y en paralelo (retros pendientes perdidas con `git worktree remove`; lock de `.git/config` en `worktree add`). (#39, #40, 2026-10)
- En los scripts que toman un issue, asigná al final, después de todo lo que puede fallar: si falla antes, el issue queda asignado sin trabajo. (#40, 2026-10)
- Para testear scripts de shell sin framework: un remoto bare local y un `gh` falso en el `PATH`, aislados de la config global de git. Modelos: `.claude/skills/mejorar-skills/test-retros.sh` y `.claude/skills/implement-issue/test-preparar.sh`. (#39, #40, 2026-10)

# Documentación de <PROJECT>

| Para | Leé |
|---|---|
| Entender qué corre hoy | [architecture.md](architecture.md) |
| Saber por qué algo es como es | [decisions/](decisions/README.md) |
| Ramas, commits, PRs y labels | [github-naming-convention.md](github-naming-convention.md) |
| Reglas para agentes | [`AGENTS.md`](../AGENTS.md) y [`llms.txt`](llms.txt) |

Reglas:
- Si `architecture.md` y el código no coinciden, gana el código y se corrige el doc **en el mismo PR**.
- Una decisión difícil de revertir va en un ADR nuevo.
- Un documento nuevo se suma a este índice y a `llms.txt`.

## Decisiones

- [ADR-002](decisions/kit/ADR-002-structured-red-validation.md) — el rojo se valida solo con un reporte estructurado (JUnit o TAP)
- TODO: `- [ADR-001](decisions/ADR-001-....md) — resumen en una línea`

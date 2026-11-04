# Documentación de <PROJECT>

| Para | Leé |
|---|---|
| Entender qué corre hoy | [architecture.md](architecture.md) |
| Usar las palabras del proyecto | [glossary.md](glossary.md) |
| Conocer los contextos y sus límites | [contexts.md](contexts.md) |
| Saber por qué algo es como es | [decisions/](decisions/README.md) |
| Ramas, commits, PRs y labels | [github-naming-convention.md](github-naming-convention.md) |
| Reglas para agentes | [`AGENTS.md`](../AGENTS.md) y [`llms.txt`](llms.txt) |

Reglas:
- Si `architecture.md` y el código no coinciden, gana el código y se corrige el doc **en el mismo PR**.
- Una decisión difícil de revertir va en un ADR nuevo.
- Un documento nuevo se suma a este índice y a `llms.txt`.

## Decisiones

- [ADR-002](decisions/kit/ADR-002-structured-red-validation.md) — el rojo se valida solo con un reporte estructurado (JUnit o TAP)
- [ADR-003](decisions/kit/ADR-003-minimal-ddd-glossary-and-contexts.md) — cada proyecto recibe un glosario del dominio y un mapa de contextos, con las reglas que los agentes aplican
- [ADR-004](decisions/kit/ADR-004-orchestrate-launch-mode-per-role.md) — `/orchestrate` lanza cada rol como agente `bk` o como subagente, según `roles.yml` (aceptado)
- TODO: `- [ADR-001](decisions/ADR-001-....md) — resumen en una línea`

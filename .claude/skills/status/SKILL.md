---
name: status
description: Resume el estado actual del proyecto (versión, flujo de ramas, trabajo en curso, épicas, PRs, deuda, decisiones recientes, migraciones pendientes) y responde qué se puede empezar ya, generado en el momento desde git, GitHub y los docs. Usar con "/status", "¿en qué estado está el proyecto?", "poneme al día", "¿qué puedo hacer ahora?", "¿qué sigue?", "¿qué está bloqueado?" o al empezar una sesión nueva.
---

# Estado del proyecto

```bash
.claude/skills/status/status.sh
```

Genera el resumen en el momento desde las fuentes (git, issues, PRs, ADRs, `docs/agents-map.json`). **No se guarda en un archivo a propósito**: un resumen commiteado envejece apenas nadie lo regenera y pasa a decir algo falso con aspecto oficial.

Al responder:
- Mostrá la salida y, si el usuario quiere más, profundizá con las fuentes que cita (`architecture.md`, la épica, el ADR).
- Si algo se ve raro (un PR viejo abierto, un crítico sin asignar, una release abierta hace semanas), mencionalo en una línea.

## Qué se puede hacer ahora

Para "¿qué puedo hacer ahora?", "¿qué sigue?", "¿qué está bloqueado?":

```bash
.claude/skills/status/available.sh
```

Devuelve cuatro listas: **se pueden empezar ya** (sin bloqueantes abiertos ni asignados, por prioridad), **en curso** (asignados o con un PR abierto que los cierra, con quién y qué PR), **bloqueados** (con lo que los bloquea) y **épicas en curso** (con avance de sub-issues). Las épicas no aparecen como disponibles: se trabajan por sus sub-issues. Los tomados tampoco: `/implement-issue` asigna el issue al tomarlo, y un PR abierto que lo cierra (por `Closes #n` en el cuerpo o por el número en la rama) también cuenta. Así dos sesiones no eligen el mismo.

Al responder:
- Mostrá la salida tal cual, sin inventar issues que no están.
- Si el usuario dice en qué área o con qué prioridad quiere trabajar, filtrá la lista con eso.
- Si hay disponibles con `status:triage`, mencionalo: todavía no tienen prioridad.
- GitHub tarda unos segundos en actualizar el resumen de dependencias: si un issue se cerró recién, puede seguir figurando unos segundos más.

No modifica nada, así que no hace falta confirmación.

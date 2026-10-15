---
name: add-member
description: Agrega un integrante al equipo del proyecto (o edita sus áreas) para que reciba issues asignados automáticamente. Usar con "/add-member @usuario", "sumá a X al equipo", "X ahora cubre pagos", "listá el equipo".
---

# Agregar integrante

El equipo vive en `.github/team.json` y lo usan `create-issue` y `plan-feature` para asignar cada issue nuevo: entre los integrantes activos que cubren alguna `area:` del issue, el de menos issues abiertos; si nadie cubre el área, el de menos carga de todo el equipo.

1. **Datos:** usuario de GitHub (obligatorio), nombre y las áreas que cubre (labels `area:` de `.github/labels.yml`). Si el usuario no dice áreas, preguntá; sin áreas recibe issues de cualquier área.
2. **Agregar o editar** (si ya está, actualiza nombre o áreas):
   ```bash
   python3 scripts/agents/team.py add <login> --name "<Nombre>" --areas area:x,area:y
   ```
   Valida que el usuario exista y tenga acceso al repo (GitHub no deja asignar issues a quien no lo tiene). Si falta la invitación, decilo; `--force` solo si el usuario confirma que la invitación está pendiente.
3. **Ver el equipo:** `python3 scripts/agents/team.py list` (con la carga de cada uno).
4. **Commitear** `.github/team.json` en una rama y abrir un PR (`chore: …`): el equipo es configuración del repo y entra por PR como todo lo demás.

Para pausar a alguien sin quitarlo (vacaciones, otra prioridad): `team.py pause <login>` / `activate <login>`.

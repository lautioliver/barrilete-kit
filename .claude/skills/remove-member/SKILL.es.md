---
name: remove-member
description: Quita o pausa a un integrante del equipo para que deje de recibir issues asignados automáticamente. Usar con "/remove-member @usuario", "sacá a X del equipo", "X se va de vacaciones".
---

# Quitar integrante

1. **¿Quitar o pausar?** Si es temporal (vacaciones, otra prioridad), pausá: sigue en el equipo pero no recibe issues nuevos.
   ```bash
   python3 scripts/agents/team.py pause <login>    # or: activate <login>
   python3 scripts/agents/team.py remove <login>
   ```
2. **Sus issues abiertos siguen asignados.** Listalos (`gh issue list --assignee <login> --state open`) y preguntá si reasignarlos. Para reasignar cada uno al que corresponde según el equipo:
   ```bash
   nuevo=$(python3 scripts/agents/team.py suggest --labels "<labels del issue separados por coma>")
   gh issue edit <n> --remove-assignee <login> --add-assignee "$nuevo"
   ```
   Mostrá la lista de reasignaciones y esperá un "sí" antes de aplicarla.
3. **Commitear** `.github/team.json` en una rama y abrir un PR.

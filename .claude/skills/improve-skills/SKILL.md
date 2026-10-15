---
name: improve-skills
description: Consolida las retros del flujo con agentes y las señales objetivas (fallas de CI en ramas de agentes, reverts) y propone ajustes a las skills en un PR que revisa una persona. Nunca edita las skills sin PR ni afloja controles. Usar con "/improve-skills", "¿qué aprendimos de las últimas corridas?", "ajustá las skills con el uso" o en la corrida semanal programada.
---

# Mejorar las skills con el uso

Las skills aprenden de su uso, pero **no se reescriben solas**: esta skill propone, una persona decide. Un ajuste sin control se ajusta a un solo caso, alarga las skills y, sobre todo, tiende a sacar los controles que frenan al agente, que son justo lo más valioso.

## 1. Juntar las señales

```bash
.claude/skills/improve-skills/signals.sh [días]
```

Trae las retros nuevas de la rama `agents/retros` (desde `consolidated.md`; un archivo por retro, con `skill_sha` para saber con qué versión de la skill se hizo, y `model` y `role` para saber quién la hizo) y las de la rama vieja `agentes/retros` (0.9), que no se reescribe: las claves y valores viejos se muestran con los nuevos, así cuentan como el mismo grupo y las señales objetivas: fallas de CI en ramas `claude/` agrupadas por workflow, y reverts. Las señales objetivas pesan más que las retros: el agente no ve sus propios puntos ciegos.

Si no hay nada nuevo, decilo y terminá.

## 2. Agrupar por patrón

Para cada patrón: qué pasó, en qué casos (links), y qué skill o script lo habría evitado. Un patrón es algo que se repite o que fue grave; una anécdota no es un patrón.

Agrupá los desvíos y hallazgos por `model` y por `role`. Si un mismo modelo falla repetido en un tipo de issue (`type:` o `area:`), es un caso para la regla de ruteo de `orchestrate` (qué issues van a Haiku y cuáles a Sonnet): se propone en el PR, sin aflojar el escalado de `agents_map.py` ni el revisor. Las retros con `model: unknown` o `role: session` no entran en esa comparación.

## 3. Decidir qué proponer

Reglas, en este orden:

1. **Al menos dos casos, o uno grave.** Grave: un bug que llegó a la revisión o a producción, una regla de negocio rota, datos o dinero en riesgo.
2. **Nunca quitar ni aflojar** reglas de Autonomía (`AGENTS.md`), aprobaciones, verificaciones ni el "no mergea / no aprueba". Si un control frena seguido sin motivo, se plantea como **pregunta para el equipo** en el PR, no como cambio.
3. **Script antes que texto.** Si se puede verificar mecánicamente (un check de CI, un control en `verify.py` o `prepare.sh`), eso; una instrucción más en Markdown es el último recurso. Las instrucciones son lo que el agente se saltea.
4. **Largo máximo:** ninguna `SKILL.md` pasa de 120 líneas. Si un ajuste no entra, hay que sacar o pasar a script otra cosa.
5. **Un cambio por patrón**, con su motivo y los casos que lo justifican.
6. **Lecciones:** lo que sirve pero no alcanza para cambiar una skill (un caso, o algo que no se puede verificar con un script) va a `docs/agents/lessons.md`, en el mismo PR. Es lo único de las retros que leen los demás agentes: nunca leen retros crudas. Máximo 40 líneas (lo controla `check-docs.py`): si no entra, sacá la lección más vieja o la que ya pasó a una skill.

## 4. Proponer en un PR

Rama `claude/<n>-improve-skills-<fecha>` (con un issue `type:task`), base la rama troncal de trabajo. El cuerpo del PR:

```markdown
## Patrones encontrados
| Patrón | Casos | Ajuste propuesto |
## Preguntas para el equipo
(controles que frenan seguido; nada de esto se cambia en este PR)
## Descartado
(anécdotas o casos que no alcanzan las reglas)
```

Mostrá el borrador del PR antes de abrirlo y esperá un "sí".

## 5. Marcar lo consolidado

Abierto el PR, marcá hasta dónde consolidaste con el commit que imprimió `signals.sh` ("consolidate up to"):

```bash
.claude/skills/improve-skills/retro.sh --consolidated <commit> <link al PR>
```

`signals.sh` imprime un commit por cada rama (la nueva y la 0.9): marcá cada uno. Escribe `consolidated.md` en la rama `agents/retros` (el punto de la rama 0.9 va ahí también: esa rama no se toca); la próxima corrida empieza desde ahí. Usá ese commit y no la punta actual: así no se saltean retros que llegaron mientras armabas el PR.

## Programarla

Para que corra sola (por ejemplo, los lunes), usá una tarea programada que ejecute `/improve-skills`. Igual termina en un PR para revisar: programarla no le da permiso para mergear.

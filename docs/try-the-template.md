# Probar la plantilla

Gracias por probarla. Lo que más sirve es saber **dónde te trabaste**, no si te gustó.

Leé esta guía [en el repo de la plantilla](https://github.com/lautioliver/barrilete-kit/blob/main/docs/probar-la-plantilla.md), no en tu copia: `init-plantilla.sh` la borra en el paso 2.

**Tiempo:** de 1 a 2 horas. **Herramienta:** la que uses todos los días (Claude Code, Codex, Copilot, Cursor…). Si no es Claude Code, mejor: es lo que menos se probó.

Los pasos usan los comandos de Claude Code (`/implement-issue 3`). En otra herramienta, si no reconoce el comando, pedíselo por nombre: "seguí la skill implement-issue (`.claude/skills/implement-issue/SKILL.md`) para el issue 3". Anotá si tuviste que hacerlo: también es un dato.

## Antes de empezar

- Un repo tuyo donde puedas romper cosas: uno chico real o uno nuevo de prueba.
- `gh` autenticado (`gh auth status`), `jq` y `python3`.
- Una nota abierta para ir anotando. Anotá en el momento: después se olvida dónde dudaste.

## Pasos

Hacelos en orden y anotá qué pasó en cada uno. Si algo no anda, no lo arregles en silencio: anotalo y seguí como puedas.

1. **Crear el repo:** en GitHub, **Use this template → Create a new repository**, y clonalo.
2. **Inicializar:** seguí el [README](../README.md#empezar). Elegí el modo que te corresponda: chico si son una o dos personas.
3. **Completar lo mínimo:** los `TODO:` que el README marca como mínimos. Anotá cuánto tardaste y qué no entendiste.
4. **Labels y equipo:** corré el workflow Labels y, en modo completo, sumá a tu equipo con `/add-member`.
5. **Un issue desde el chat:** pedile al agente algo real y chico ("abrí un issue para …").
6. **Del issue al PR:** `/implement-issue <n>`. No lo mergees sin leerlo.
7. **Revisión** (modo completo): `/review-pr <n>` desde **otra sesión**.
8. **Merge:** lo hacés vos.
9. **Si te queda tiempo:** `/orquestar` con dos o tres issues (modo completo, Claude Code), o repetí los pasos 5 a 7 en otra herramienta.

## Qué anotar

- **Dónde te trabaste:** el paso, qué hiciste y el error textual.
- **Qué leíste dos veces** sin entenderlo.
- **Qué hiciste a mano** cuando esperabas que lo hiciera el agente, o al revés.
- **Qué hizo el agente que no esperabas:** se frenó, preguntó de más, se salteó algo, tocó lo que no debía.
- **Cuánto tardaste** en llegar al primer PR.
- **Si la volverías a usar** y qué cambiarías primero.

## Cómo contarlo

Abrí un issue con el formulario [**Reporte de prueba**](https://github.com/lautioliver/barrilete-kit/issues/new?template=5-prueba.yml) (`.github/ISSUE_TEMPLATE/5-prueba.yml`). Usá un reporte por prueba, aunque te hayas trabado en varios pasos. Pegá los errores textuales y **sacá los secretos y los datos personales** antes de pegar.

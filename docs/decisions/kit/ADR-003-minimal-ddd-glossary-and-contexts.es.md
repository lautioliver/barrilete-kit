# ADR-003 — DDD mínimo: glosario y mapa de contextos en cada proyecto

## Estado

Aceptado (2026-11-02)

Origen: épica lautioliver/barrilete-kit#214 ("Traer lo mínimo de Domain-Driven Design a todos los proyectos") y su primer issue, lautioliver/barrilete-kit#215. Las decisiones 1 a 7 de la épica las aprobó @lautioliver en el chat el 2026-11-02, y se registran abajo tal como se aprobaron, sin cambios. Donde una regla dice "aprobado por @lautioliver en el chat (2026-11-02)", esa es la aprobación.

## Contexto

- El kit no tiene un vocabulario compartido para el dominio de un proyecto ni un mapa de sus contextos acotados. Los agentes leen `docs/reference/domain.md` y `docs/reference/modules.md`, que describen entidades y módulos, no los límites entre ellos.
- `docs/reference/glossary.md` ya existe en el perfil completo, como plantilla `TODO`. Nadie la lee: ninguna skill ni ningún check la usa.
- `--small` borra `docs/reference/` entero (`profiles/small/DELETE`), así que el perfil chico no tiene glosario. Su `docs/agents-map.json` tiene solo `red`, y `check-docs.py` lo trata aparte (`SOLO_RED`) sin validar `required`.
- `implement-issue` ya lee "lo que aplique de `docs/reference/`", `plan-feature` la nombra en general, y `review-pr` no tiene fila de lenguaje ni de límites de contexto. El perfil `--small` no trae `plan-feature` ni `review-pr`.
- Todo proyecto creado con el kit recibiría las mismas reglas. Sacarlas después es una ruptura para los proyectos que ya las siguen, así que lo decidido en el chat tiene que quedar escrito donde los agentes lo leen.

## Decisión

1. **D1. El kit tiene un ADR, en `docs/decisions/kit/`.** Este documento es `kit/ADR-003`. Es el primer issue de la épica #214.

2. **D2. Dónde viven el glosario y el mapa.**
   - **Perfil completo:** `docs/reference/glossary.md` (ya existe) y docs/reference/contexts.md (nuevo).
   - **Perfil `--small`:** docs/glossary.md y docs/contexts.md, planos, como docs/architecture.md.
   - `grow.py` mueve los archivos del perfil chico a `docs/reference/` cuando un proyecto pasa al perfil completo.

3. **D3. Qué código es de qué contexto.**
   - **Perfil completo:** una sección nueva `contexts` en `docs/agents-map.json`, con entradas de la forma `[{"name": "...", "paths": ["<glob>"], "depends_on": ["<name>"]}]`: `name`, `paths` (globs) y `depends_on` (los nombres de otros contextos). `agents_map.py` la usa para decir qué contextos toca un diff, y `check-docs.py` la valida. Existe solo en el perfil completo.
   - **Perfil `--small`:** solo la tabla de docs/contexts.md. El mapa chico sigue teniendo solo `red` (ADR-002 D2).

4. **D4. Qué cuenta como cruzar un límite.** Una dependencia nueva entre contextos que no está en `depends_on` (o, en `--small`, no está en la tabla). Tocar dos contextos en un mismo PR es una señal para el revisor, no una infracción.

5. **D5. Cómo valida `check-docs.py` en `--small`.** En el caso `SOLO_RED` exige los dos archivos por una ruta fija. No se agrega una entrada `required` al mapa chico.

6. **D6. Severidad en `review-pr`.**
   - Un cruce de contexto sin ADR es **a corregir**.
   - Un término de dominio que no está en el glosario es una **sugerencia**: agregarlo al glosario o usar el término existente.
   - "Bloqueante" queda reservado para reglas de negocio.

7. **D7. Glosario vacío (`TODO`).** Las reglas no bloquean. El agente propone términos en su PR. `check-docs.py` solo verifica que los archivos existan y estén enlazados, no lo que dicen.

**Migraciones.** No hay migración de esquema. Del kit: `update.py` e `install.py` traen los archivos nuevos (el glosario completo ya existe); `grow.py` mueve los archivos chicos a `docs/reference/`; un mapa sin sección `contexts` se lee como vacío.

## Alternativas rechazadas

- **Patrones tácticos en el glosario (agregados, repositorios, eventos de dominio).** Son una decisión de arquitectura de cada proyecto, no un mínimo que todos necesiten. Quedan fuera de alcance.
- **Analizar imports, por lenguaje, para detectar cruces de contexto.** Necesitaría un parser por lenguaje. La declaración `depends_on` es explícita y sirve para cualquier stack (D3, D4).
- **Una sección `contexts` en el mapa chico.** Metería la complejidad del mapa completo en el perfil que deliberadamente tiene solo `red` (ADR-002 D2). El perfil chico usa la tabla de docs/contexts.md (D3, D5).
- **Una entrada `required` en el mapa chico.** Por la misma razón: las rutas fijas de D5 lo cubren sin cambiar el mapa chico.

## Consecuencias

- `review-pr` puede marcar cruces y términos no definidos con la severidad de D6. El riesgo es el ruido: por eso solo se marcan los nombres del dominio en el código y los docs que cambian, y los términos llegan como sugerencias.
- Cada skill que lee el glosario recibe una línea que remite a este ADR, para que las skills no pasen su límite de 120 líneas.
- Un proyecto instalado con `install.py` que ya tiene su glosario en otra ruta recibe una advertencia del instalador. El instalador no lo pisa.
- Las secciones nuevas de `docs/agents-map.json` y los tests de CI del init y del update son rutas sensibles: la aprobación es la que queda registrada en este ADR, y el cambio lo revisan los tests de `test-init.sh`, `check-docs.py`, `agents_map.py`, `test-update.sh`, `test-install.sh`, el test de `grow` y `test-i18n.sh`.
- Fuera de alcance: llenar el glosario del propio kit, y cualquier check que lea el contenido del glosario.

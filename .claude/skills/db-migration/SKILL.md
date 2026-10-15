---
name: db-migration
description: Planifica y escribe cambios de schema y migraciones de base de datos de forma segura (compatibilidad, backfill, rollback, validación). Usar siempre que un cambio toque el schema o las migraciones, con "/db-migration", "agregá una columna", "cambiá la tabla X" o similar.
---

# Migración de base de datos

Un cambio de schema es de lo más difícil de revertir: los datos ya migrados no vuelven solos. Por eso requiere aprobación (AGENTS.md, Autonomía) y este plan **antes** de escribir la migración.

Los comandos concretos (generar migración, correrla local, tests) están en `AGENTS.md`. TODO: si el proyecto tiene herramienta de migraciones (Drizzle, Prisma, Alembic, SQL a mano…), documentá acá sus particularidades.

## 1. Plan (mostrarlo y esperar aprobación)

Tocar el schema también requiere la aprobación de Autonomía: pedí las dos en el mismo mensaje, con esta tabla. Después la tabla va completa al PR.

| Punto | Qué responder |
|---|---|
| Schema actual | Tablas/columnas/índices/constraints involucrados, tal como están hoy (leelo del código del schema, no de memoria). |
| Schema deseado | El cambio exacto. |
| Compatibilidad | ¿El código desplegado hoy sigue funcionando con el schema nuevo? (durante el deploy conviven versiones). ¿Hay lectores externos (reportes, otros servicios)? |
| Migración | Pasos SQL. ¿Bloquea la tabla? ¿Cuánto tarda con el volumen de producción? |
| Backfill | ¿Hay que completar datos existentes? ¿Cómo, en lotes, idempotente? |
| Rollback | Cómo se vuelve atrás. Si no se puede sin perder datos, decirlo explícitamente. |
| Validación | Cómo se comprueba después que quedó bien (consultas, conteos, tests). |

## 2. Reglas

- **Cambios destructivos en dos pasos** (expand / contract): primero agregar lo nuevo y hacer que el código use ambas cosas; en un PR posterior, cuando nada usa lo viejo, borrarlo. Nunca renombrar ni borrar una columna en uso en un solo deploy.
- Columna nueva `NOT NULL` en tabla con datos: agregar nullable o con default → backfill → recién ahí `NOT NULL`.
- Índices sobre tablas grandes: de forma concurrente si el motor lo permite.
- Invariantes en la base (constraints, `CHECK`, `UNIQUE`) cuando la regla tiene que valer siempre; no solo en el código.
- Las migraciones son inmutables una vez mergeadas: si hay que corregir, migración nueva.
- **Nunca** correr migraciones contra entornos compartidos o producción. Solo local o la base de tests.

## 3. Implementar

1. Cambiar el schema y generar la migración con la herramienta del proyecto. Revisar el SQL generado línea por línea.
2. Correrla en local / tests desde cero y sobre datos existentes.
3. Tests: el comportamiento nuevo, y que los datos viejos sigan siendo válidos.
4. Docs: `docs/reference/domain.md` (y lo que diga `agents_map.py`). Si es una decisión de modelo de datos difícil de revertir, ADR.

## 4. PR

En el cuerpo del PR, la tabla del paso 1 completa, incluido el rollback. Si es un cambio en dos pasos, decir en qué paso está y abrir el issue del siguiente (`create-issue`, bloqueado por este).

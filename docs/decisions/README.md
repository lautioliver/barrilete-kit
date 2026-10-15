# Decisiones (ADRs) — <PROJECT>

Un ADR (Architecture Decision Record) registra una decisión **difícil de revertir**: de producto, de datos, de dinero, de infraestructura o legal. Explica el porqué para que nadie la deshaga sin saberlo.

## Cuándo escribir uno

- Cambia el modelo de datos de forma que no se deshace con un revert.
- Fija una regla de negocio que otros van a dar por sentada.
- Elige un proveedor, un stack o una topología.
- Contradice o reemplaza un ADR anterior.

No hace falta ADR para cosas que se revierten con un PR sin costo.

## Formato

- Archivo: `ADR-NNN-<tema-en-kebab>.md`, número correlativo de tres dígitos. Nunca se reutiliza un número.
- Partir de [`ADR-000-template.md`](ADR-000-template.md).
- Estado: `Propuesto` → `Aceptado (AAAA-MM-DD)` → opcionalmente `Reemplazado por ADR-NNN`.
- Un ADR aceptado no se reescribe. Si cambia, se agrega una sección `## Enmienda AAAA-MM-DD` o se escribe un ADR nuevo que lo reemplace.
- ADRs del kit (los que explican cómo es el kit, no el producto): línea `Ámbito: kit` debajo de `## Estado`. El init (completo y `--small`) los borra, y borra sus líneas de los índices (bloques `<!-- template:start -->` … `<!-- template:end -->`). Los ADRs de un proyecto no la llevan.
- Reglas numeradas (`R-1`, `R-2`…) cuando el código o los tests las van a citar.

## Al aceptar un ADR

1. Sumarlo al índice en `docs/README.md` y en `docs/llms.txt`.
2. Si cambia una regla ya definida, el PR lleva el label `business-logic`.
3. Si contradice código existente, abrir el issue para alinear el código (skill `create-issue`).

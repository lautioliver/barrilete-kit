---
name: debug
description: Investiga un bug separando síntoma, causa y arreglo antes de tocar código. Usar con "/debug", "esto no anda", "investigá este error", con issues type:bug (implement-issue la llama) o cuando un test falla sin causa obvia.
---

# Debug

Los agentes tienden a probar arreglos plausibles hasta que el síntoma desaparece. Eso tapa la causa y deja el bug esperando. Esta skill obliga a ir en orden: **no se escribe el arreglo hasta tener la causa raíz con evidencia.**

## 1. Reproducir

- Escribí el síntoma exacto: qué se hace, qué se espera, qué pasa (mensaje de error, valor, captura).
- Reproducilo de la forma más chica posible. Lo ideal: **un test que falla**. Si no se puede con un test, un script o pasos manuales precisos.
- Si no se reproduce, no sigas adivinando: listá qué probaste y qué datos faltan (entorno, IDs, logs) y pedilos.

## 2. Recopilar evidencia

- Leé el código del camino que falla, de la entrada al punto del error. No solo el archivo donde explota.
- Logs, stack trace, estado de la base, `git log -S` / `git blame` sobre las líneas sospechosas (¿cuándo empezó?).
- Revisá si un ADR, la auditoría o los docs dicen cómo debería comportarse. A veces el "bug" es un cambio de regla no declarado.

## 3. Causa raíz

Escribí, antes de arreglar:

> **Síntoma:** …
> **Causa:** … (archivo:línea, y por qué produce el síntoma)
> **Evidencia:** … (el test, el log, el valor que lo prueba)
> **Por qué no lo detectaron los tests:** …

Si tenés dos hipótesis, probá cuál es con evidencia; no arregles las dos "por las dudas". Si la causa está en algo sensible (AGENTS.md, Autonomía), consultá antes de seguir.

## 4. Proponer el arreglo

- El arreglo ataca la causa, no el síntoma. Si solo se puede mitigar, decilo.
- ¿Hay otros lugares con el mismo patrón? Buscalos (`grep`). Arreglalos si están en alcance; si no, issue nuevo.
- Si el usuario está presente y el arreglo no es obvio, mostrá causa + propuesta y esperá el visto bueno.

## 5. Implementar y test de regresión

- El test del paso 1 tiene que pasar de fallar a pasar con el arreglo. Si no tenías test, escribilo ahora.
- Corré la suite completa: el arreglo no puede romper otra cosa.

## 6. Dejar registro

El bloque del paso 3 va al PR (sección "Por qué") o como comentario en el issue. Es lo que le sirve a quien mire este código dentro de seis meses.

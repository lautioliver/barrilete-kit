---
skill: implement-issue
issue: 313
pr: 320
area: none
paths: scripts/test-update.sh
date: 2026-11-16
skill_sha: 2459b4d65d63ee3b83477a38543f06580fb8a3be
model: opus
role: session
---
**Deviations:** no hay commit rojo ni bloque de `red.sh`, porque el comportamiento ya existía: el PR lleva `no tests: <motivo>` y, como prueba, una mutación de `update.py` (borrar el título del aviso "conservar": fallan los casos 51, 13 y 36). El primer commit pasaba de 72 caracteres y lo corregí con amend antes del push.
**Decisions not covered:** el skill da por hecho que un PR de tests tiene rojo. Para una tarea que solo agrega cobertura a un comportamiento que ya existe, no dice cómo mostrar que el test puede fallar; usé la mutación que pedía el issue. Elegí `area:infra` porque el issue no tenía `area:`. El scope `update` sale de un precedente (#278), porque la lista de scopes sigue en TODO.
**What the review found:** `/code-review` no encontró bugs y dejó cuatro huecos de cobertura menores: el fixture 0.9 se sigue armando desde HEAD, sin guarda contra el tag `v0.9.0`; no se cubre un `lecciones.md` sin tocar; no se chequea que la ruta vieja falte del aviso; el fixture no usa el contenido real. Los dejé fuera de alcance y quedaron explicados en el PR.
**Proposal:** que el paso 3 nombre el caso "PR de solo cobertura": `no tests:` más una mutación documentada en "How to test it", en lugar de dejarlo implícito.

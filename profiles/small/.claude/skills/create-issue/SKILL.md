---
name: create-issue
description: Abre issues de GitHub a partir de un pedido en el chat, con título, labels y cuerpo según la convención del proyecto. Usar con "abrí un issue", "creá un ticket", "anotá esto como bug", "pasá estos pendientes a issues".
---

# Crear issue

Requiere `gh` autenticado (`gh auth status`). Los labels válidos son solo los de `.github/labels.yml`; no crees otros.

1. **Entender el pedido.** Separá cuántos issues son. Si falta algo imprescindible, preguntá una vez; no inventes datos.
2. **Buscar duplicados:** `gh issue list --state all --search "<palabras clave>" --limit 10`. Si hay uno abierto parecido, proponé comentar ahí.
3. **Tipo** (exactamente un `type:`) y **secciones del cuerpo:**

   | Pedido | Label | Secciones |
   |---|---|---|
   | Algo no funciona | `type:bug` | Qué pasa · Qué debería pasar · Cómo reproducirlo |
   | Algo nuevo o un cambio visible | `type:feature` | Objetivo · Alcance · Listo cuando |
   | Trabajo técnico | `type:task` | Qué hay que hacer · Por qué · Listo cuando |
   | Documentación | `type:docs` | Qué hay que hacer · Por qué |

4. **Título** en imperativo, sin prefijo ni punto final: `Agregar login con Google`. En bugs vale el síntoma.
5. **Prioridad** solo si el usuario la dio o es obvia (rompe algo en uso → `priority:high`).
6. **Responsable:** `python3 scripts/agents/team.py suggest --labels "<labels separados por coma>"` devuelve a quién asignarlo según `.github/team.json` (por área y carga). Si no devuelve nada, el equipo está vacío: el issue queda sin asignar (sugerí `/add-member`). Si el usuario pidió otra persona, gana el usuario.
7. **Cuerpo:** las secciones del tipo, links a archivos con ruta relativa, nada de secretos ni datos personales.
8. **Mostrar el borrador (con el responsable) y esperar un "sí".** Abrir un issue publica contenido.
9. **Crear** con el cuerpo en un archivo temporal:
   ```bash
   gh issue create --title "<título>" --body-file <archivo> --label "type:bug" --label "priority:high" --assignee "<responsable>"
   ```
10. **Responder** con el link, o con el error si falló.

Si un issue depende de otro, decilo en el cuerpo: `Después de #12: <por qué>`.

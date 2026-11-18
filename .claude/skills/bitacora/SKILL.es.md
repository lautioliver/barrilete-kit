---
name: bitacora
description: Dibuja la idea que se está pensando en este chat como una entrada de la bitácora del proyecto (docs/bitacora.html), en la sección de un tema, con gráficos, poco texto y palabras de persona, para seguir pensándola y que quede cómo se llegó a ella. Solo cuando la persona lo pide, con "/bitacora <tema>", "guardá esto en la bitácora", "sumalo a la bitácora".
---

# Bitácora del proyecto (`/bitacora <tema>`)

El proyecto tiene **una** bitácora, `docs/bitacora.html`, versionada en git para que la tengan todos los integrantes. Tiene una sección por tema; cada `/bitacora <tema>` suma una entrada, con su fecha, **abajo** de lo que ya tenía la sección. Nada de lo escrito se reescribe: `scripts/agents/bitacora_add.py` solo inserta, y crea el archivo la primera vez.

Correlo solo cuando la persona lo pide. La bitácora es para **pensar ideas**, no para informar trabajo: lo que se tocó, cómo se verificó y qué falló ya está en los PRs y en las retros. La entrada dibuja la idea que se viene hablando en **esta conversación** para que la persona la siga pensando y para que, cuando se construya, quede cómo se llegó a ella. Es para una persona que no lee código.

## 1. Buscar la sección

```bash
python3 scripts/agents/bitacora_add.py find --topic "<tema>"
```

- `exact <slug>` (sale con 0): la sección existe; la entrada va abajo.
- `none <slug>` (sale con 0): no hay sección; se crea al final.
- `similar <slug>\t<tema>` (sale con 3), una línea por cada sección con un nombre parecido: **preguntale a la persona antes de escribir**, nombrando las secciones que encontró ("¿Te referís a la sección «Decidir la ruta» o es una nueva?"). Su respuesta decide el flag del paso 3: `--into <slug>` para una sección que existe, `--new` para una nueva. Sin respuesta, no escribas.

Si no te pasaron `<tema>`, proponé uno en pocas palabras a partir de la conversación y confirmalo antes del paso 3.

## 2. Escribir la entrada

Un archivo con un fragmento HTML (sin `<html>`, `<head>` ni `<body>`), en el idioma de la instalación (`language` de `.agent-kit.json`; sin él, `en`). No repitas la fecha ni el tema: los escribe el script.

Cómo se escribe:
- **Gráficos primero.** Empezá con un dibujo (pasos, ramas, mapa, comparación) y después el texto que lo explica. Si algo se puede mostrar, no lo cuentes.
- **Poco texto.** Frases cortas: qué hace cada parte y por qué.
- **Palabras de persona,** sin nombres de archivos, rutas, comandos, funciones, códigos de salida ni números de PR o de commit. Si una parte del sistema importa, nombrala por lo que hace («el paso que revisa la entrada»), no por su archivo.
- **Todo el camino de la idea:** de dónde salió, qué opciones hubo, qué se descartó y por qué, qué se decidió y qué falta, con quién tiene que decidir.

Qué lleva, en este orden y salteando lo que no aplica:
1. **La idea en una frase**, en una nota.
2. **Cómo funciona**, con un flujo o un mapa de partes.
3. **Las opciones**: un diagrama con ramas, con la elegida y las descartadas, y por qué.
4. **Lo decidido** y **lo que falta**, con tarjetas por estado.

Componentes (la página ya trae sus estilos y usan los tokens del diseño):

| Componente | Para qué | HTML |
|---|---|---|
| Diagrama con ramas | una pregunta y sus opciones | `<div class="branch"><div class="root">¿Dónde se guarda?</div><div class="opts"><div class="opt ok"><h4>Un archivo</h4><p>Elegida: …</p></div><div class="opt danger"><h4>Uno por tema</h4><p>Descartada: …</p></div></div></div>` |
| Mapa de partes | cómo se conectan las partes | `<ul class="map"><li><span class="node">El chat</span><span class="edge">escribe en</span><span class="node">La bitácora</span></li></ul>` |
| Flujo | pasos en orden | `<ol class="flow"><li>charlamos</li><li>se dibuja</li><li>se decide</li></ol>` |
| Tabla | comparar | `<table class="tbl"><tr><th>Antes</th><th>Después</th></tr><tr><td>…</td><td>…</td></tr></table>` |
| Tarjetas por estado | decidido, en curso, te espera | `<div class="cards"><div class="card ok"><h3>Decidido</h3><p>…</p></div><div class="card warn"><h3>En curso</h3><p>…</p></div><div class="card danger"><h3>Te espera a vos</h3><p>…</p></div></div>` |
| Números clave | un número que importa | `<div class="kpis"><div class="kpi ok"><b>3</b> pasos</div></div>` |
| Barras | proporciones, avance | `<div class="bars"><div class="bar ok"><span>Hecho</span><i style="--v:70%"></i></div></div>` |
| Nota | la idea en una frase, un aviso | `<div class="note"><p><strong>La idea.</strong> …</p></div>` |
| Estado en el texto | | `<span class="ok">hecho</span>`, `<span class="warn">en curso</span>`, `<span class="danger">te espera a vos</span>` |

Colores de estado: `ok` hecho o elegida, `warn` en curso, `danger` espera a una persona, está roto o se descartó. Nunca solo el color: la palabra también lo dice. En un mapa, `node` también acepta `ok`, `warn` y `danger`.

Usá solo estos componentes y etiquetas de texto simples (`p`, `strong`, `em`, `ul`/`ol`/`li`, `a href`, `h3`, `h4`…): el script revisa el fragmento contra una lista permitida y rechaza (sale con 64 y no toca el archivo) todo lo demás, como scripts, estilos, manejadores `on…=`, `javascript:`, comentarios, etiquetas de la estructura de la página, un `<` suelto (escribí `&lt;`, que pasa), etiquetas que quedan abiertas (`<b/>` la deja abierta: cerrala con `</b>`; solo `<br/>` y `<hr/>` se cierran solas; `</br>` no pasa), links a otro sitio sin esquema (`//host`) o una etiqueta a medio escribir al final (`<b`). Su mensaje dice qué estaba mal: arreglá el fragmento y probá de nuevo.

## 3. Agregarla

```bash
python3 scripts/agents/bitacora_add.py add --topic "<tema>" --entry <fragmento.html> [--into <slug> | --new]
```

Imprime `ok: new <slug> <ruta>` (sección nueva) u `ok: append <slug> <ruta>` (entrada abajo). Sale con 3: hay secciones parecidas y no pasaste `--into` ni `--new` (volvé al paso 1). Sale con 65: el archivo se editó a mano y perdió sus marcadores; no se toca: avisale a la persona.

Escribí el fragmento en un archivo temporal fuera del repo y borralo después. No edites `docs/bitacora.html` a mano: el script es lo que garantiza que no se reescribe nada de arriba.

## 4. Avisarle a la persona

Una línea con la sección y el link: `docs/bitacora.html#<slug>`. El archivo es versionado: commitealo en la rama en la que estás trabajando, o decile a la persona que queda para commitear. No abras un PR solo para la bitácora salvo que lo pida.

Tokens del diseño: `scripts/agents/bitacora/barrilete.css`; un proyecto los pisa en su propio .barrilete/bitacora.css, que se lee al crear la página. El detalle está en el doc de la bitácora del kit (docs/agents/bitacora.md, que el modo `--small` no instala).

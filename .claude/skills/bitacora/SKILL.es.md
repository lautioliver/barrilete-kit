---
name: bitacora
description: Dibuja la idea que se está pensando en este chat como una entrada de la bitácora del proyecto (docs/bitacora.html y una página por mes en docs/bitacora/), en la sección de un tema, con gráficos, poco texto y palabras de persona, para seguir pensándola y que quede cómo se llegó a ella. Solo cuando la persona lo pide, con "/bitacora <tema>", "guardá esto en la bitácora", "sumalo a la bitácora".
---

# Bitácora del proyecto (`/bitacora <tema>`)

El proyecto tiene **una** bitácora, versionada en git para que la tengan todos los integrantes, partida por mes: `docs/bitacora.html` es la portada (el índice de meses y una sección por tema, con un enlace a cada mes donde el tema tiene entradas) y las entradas están en la página de su mes, `docs/bitacora/AAAA-MM.html`, con una sección por tema. Cada `/bitacora <tema>` suma una entrada, con su fecha, **abajo** de lo que ese tema ya tenía en el mes. Nada de lo escrito se reescribe: `scripts/agents/bitacora_add.py` solo inserta, solo escribe la página del mes en curso (las de los meses pasados no se tocan) y crea las páginas la primera vez. Una bitácora de antes de partirla (todas las entradas en `docs/bitacora.html`) pasa sin cambios a `docs/bitacora-anterior.html` con la primera entrada nueva, y la portada la enlaza.

Correlo solo cuando la persona lo pide. La bitácora es para **pensar ideas**, no para informar trabajo: lo que se tocó, cómo se verificó y qué falló ya está en los PRs y en las retros. La entrada dibuja la idea que se viene hablando en **esta conversación** para que la persona la siga pensando y para que, cuando se construya, quede cómo se llegó a ella. Es para una persona que no lee código.

## 1. Buscar la sección

```bash
python3 scripts/agents/bitacora_add.py find --topic "<tema>"
```

- `exact <slug>` (sale con 0): el tema existe, en cualquier mes; la entrada va abajo (si el tema todavía no tiene sección en la página de este mes, se la abre).
- `none <slug>` (sale con 0): no hay un tema; su sección se crea al final.
- `similar <slug>\t<tema>` (sale con 3), una línea por cada sección con un nombre parecido: **preguntale a la persona antes de escribir**, nombrando las secciones que encontró ("¿Te referís a la sección «Decidir la ruta» o es una nueva?"). Su respuesta decide el flag del paso 3: `--into <slug>` para una sección que existe, `--new` para una nueva. Sin respuesta, no escribas.

Si no te pasaron `<tema>`, proponé uno en pocas palabras a partir de la conversación y confirmalo antes del paso 3.

## 2. Escribir la entrada

Un archivo con un fragmento HTML (sin `<html>`, `<head>` ni `<body>`), en el idioma de la instalación (`language` de `.agent-kit.json`; sin él, `en`). No repitas la fecha ni el tema: los escribe el script.

Cómo se escribe:
- **Gráficos primero.** Empezá con un dibujo (pasos, ramas, mapa, comparación) y después el texto que lo explica. Si algo se puede mostrar, no lo cuentes.
- **Poco texto.** Frases cortas: qué hace cada parte y por qué.
- **Links.** La entrada vive en `docs/bitacora/`: un link a otro tema es `../bitacora.html#<slug>` (su sección en la portada, con sus meses), y un link relativo a un doc necesita `../` adelante.
- **Palabras de persona,** sin nombres de archivos, rutas, comandos, funciones, códigos de salida ni números de PR o de commit. Si una parte del sistema importa, nombrala por lo que hace («el paso que revisa la entrada»), no por su archivo.
- **Todo el camino de la idea:** de dónde salió, qué opciones hubo, qué se descartó y por qué, qué se decidió y qué falta, con quién tiene que decidir.

Qué lleva, en este orden y salteando lo que no aplica:
1. **Cómo funciona**, con un flujo o un mapa de partes: la entrada empieza con este dibujo.
2. **La idea en una frase**, en una nota justo debajo.
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

En `.opts` van solo `.opt`, dos o tres: las líneas que las unen cuentan con eso.

Una página creada antes de los diagramas no trae sus estilos (el diseño se copia al crearla): si el `<style>` de la página del mes (`docs/bitacora/AAAA-MM.html`) no tiene una regla `.branch{` ni `.map{` (buscá la regla, no la palabra, que puede estar en una entrada), dibujá las opciones con tarjetas o una tabla y las partes con un flujo.

Colores de estado: `ok` hecho o elegida, `warn` en curso, `danger` espera a una persona, está roto o se descartó. Nunca solo el color: la palabra también lo dice. En un mapa, `node` también acepta `ok`, `warn` y `danger`.

Usá solo estos componentes y etiquetas de texto simples (`p`, `strong`, `em`, `ul`/`ol`/`li`, `a href`, `h3`, `h4`…): el script revisa el fragmento contra una lista permitida y rechaza (sale con 64 y no toca el archivo) todo lo demás, como scripts, estilos, manejadores `on…=`, `javascript:`, comentarios, etiquetas de la estructura de la página, un `<` suelto (escribí `&lt;`, que pasa), etiquetas que quedan abiertas (`<b/>` la deja abierta: cerrala con `</b>`; solo `<br/>` y `<hr/>` se cierran solas; `</br>` no pasa), links a otro sitio sin esquema (`//host`) o una etiqueta a medio escribir al final (`<b`). Su mensaje dice qué estaba mal: arreglá el fragmento y probá de nuevo.

## 3. Agregarla

```bash
python3 scripts/agents/bitacora_add.py add --topic "<tema>" --entry <fragmento.html> [--into <slug> | --new]
```

Imprime `ok: new <slug> <ruta>` (tema nuevo) u `ok: append <slug> <ruta>` (el tema ya existía, en cualquier mes); `<ruta>` es la página del mes. Sale con 3: hay secciones parecidas y no pasaste `--into` ni `--new` (volvé al paso 1). Sale con 64 también con un `--date` futuro o de un mes anterior a la página más nueva: las páginas de los meses pasados no se tocan. Sale con 65: una página se editó a mano y perdió sus marcadores, o `docs/bitacora-anterior.html` ya existe y no se puede mover ahí la bitácora de antes; no se toca nada: avisale a la persona.

No pases `--date` (es hoy) salvo que la persona pida otro día de este mes.

Escribí el fragmento en un archivo temporal fuera del repo y borralo después. No edites a mano `docs/bitacora.html` ni las páginas de `docs/bitacora/`: el script es lo que garantiza que no se reescribe nada de arriba.

## 4. Avisarle a la persona

Una línea con la sección y el link: `docs/bitacora/AAAA-MM.html#<slug>`. Los archivos son versionados: commiteá la portada y la página del mes (y `docs/bitacora-anterior.html`, si se acaba de mover) en la rama en la que estás trabajando, o decile a la persona que quedan para commitear. No abras un PR solo para la bitácora salvo que lo pida.

Diseño: `scripts/agents/bitacora/barrilete.css`, uno solo para todos los proyectos que usan barrilete-kit y siempre claro; un proyecto no lo cambia. El detalle está en el doc de la bitácora del kit (docs/agents/bitacora.md, que el modo `--small` no instala).

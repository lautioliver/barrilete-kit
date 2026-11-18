---
name: bitacora
description: Guarda lo que se está hablando en este chat como una entrada de la bitácora del proyecto (docs/bitacora.html), en la sección de un tema, con números, tablas y colores de estado para que una persona lo lea de un vistazo. Solo cuando la persona lo pide, con "/bitacora <tema>", "guardá esto en la bitácora", "sumalo a la bitácora".
---

# Bitácora del proyecto (`/bitacora <tema>`)

El proyecto tiene **una** bitácora, `docs/bitacora.html`, versionada en git para que la tengan todos los integrantes. Tiene una sección por tema; cada `/bitacora <tema>` suma una entrada, con su fecha, **abajo** de lo que ya tenía la sección. Nada de lo escrito se reescribe: `scripts/agents/bitacora_add.py` solo inserta, y crea el archivo la primera vez.

Correlo solo cuando la persona lo pide. La entrada se escribe con **esta conversación**: qué cambió y por qué, qué se decidió, cómo se verificó y qué sigue abierto. Es para una persona que no estuvo en el chat.

## 1. Buscar la sección

```bash
python3 scripts/agents/bitacora_add.py find --topic "<tema>"
```

- `exact <slug>` (sale con 0): la sección existe; la entrada va abajo.
- `none <slug>` (sale con 0): no hay sección; se crea al final.
- `similar <slug>\t<tema>` (sale con 3), una línea por cada sección con un nombre parecido: **preguntale a la persona antes de escribir**, nombrando las secciones que encontró ("¿Te referís a la sección «Decidir la ruta» o es una nueva?"). Su respuesta decide el flag del paso 3: `--into <slug>` para una sección que existe, `--new` para una nueva. Sin respuesta, no escribas.

Si no te pasaron `<tema>`, proponé uno en pocas palabras a partir de la conversación y confirmalo antes del paso 3.

## 2. Escribir la entrada

Un archivo con un fragmento HTML (sin `<html>`, `<head>` ni `<body>`), en el idioma de la instalación (`language` de `.agent-kit.json`; sin él, `en`), en palabras simples. No repitas la fecha ni el tema: los escribe el script. Que sea corta: lo que alguien necesita para retomar la idea.

Qué lleva, en este orden y salteando lo que no aplica:
1. **Qué cambió y por qué**, en uno o dos `<p>`.
2. **Un número o un gráfico cuando ayude**: antes/después, avance, un flujo.
3. **Decisiones**: las tomadas y las que siguen abiertas, con quién tiene que decidir.
4. **Qué sigue**, con su estado.

Componentes (la página ya trae sus estilos; usan los tokens del diseño y andan en modo claro y oscuro):

| Componente | HTML |
|---|---|
| Números clave | `<div class="kpis"><div class="kpi ok"><b>12</b> casos pasan</div><div class="kpi warn"><b>2</b> abiertos</div></div>` |
| Tarjetas por estado | `<div class="cards"><div class="card ok"><h3>Hecho</h3><p>…</p></div><div class="card warn"><h3>En curso</h3><p>…</p></div><div class="card danger"><h3>Te espera a vos</h3><p>…</p></div></div>` |
| Tabla (antes/después, opciones) | `<table class="tbl"><tr><th>Antes</th><th>Después</th></tr><tr><td>…</td><td>…</td></tr></table>` |
| Barras | `<div class="bars"><div class="bar ok"><span>Hecho</span><i style="--v:70%"></i></div></div>` |
| Flujo | `<ol class="flow"><li>issue</li><li>rojo</li><li>verde</li><li>PR</li></ol>` |
| Nota | `<div class="note warn"><p>…</p></div>` |
| Estado en el texto | `<span class="ok">hecho</span>`, `<span class="warn">en curso</span>`, `<span class="danger">te espera a vos</span>` |

Colores de estado: `ok` hecho, `warn` en curso, `danger` espera a una persona o está roto. Nunca solo el color: la palabra también lo dice.

Usá solo estos componentes y etiquetas de texto simples (`p`, `strong`, `em`, `code`, `ul`/`ol`/`li`, `a href`, `h3`…): el script revisa el fragmento contra una lista permitida y rechaza (sale con 64 y no toca el archivo) todo lo demás, como scripts, estilos, manejadores `on…=`, `javascript:`, comentarios, etiquetas de la estructura de la página, un `<` suelto (escribí `&lt;`, que pasa), etiquetas que quedan abiertas (`<b/>` la deja abierta: cerrala con `</b>`; solo `<br/>` y `<hr/>` se cierran solas; `</br>` no pasa), links a otro sitio sin esquema (`//host`) o una etiqueta a medio escribir al final (`<b`). Su mensaje dice qué estaba mal: arreglá el fragmento y probá de nuevo.

## 3. Agregarla

```bash
python3 scripts/agents/bitacora_add.py add --topic "<tema>" --entry <fragmento.html> [--into <slug> | --new]
```

Imprime `ok: new <slug> <ruta>` (sección nueva) u `ok: append <slug> <ruta>` (entrada abajo). Sale con 3: hay secciones parecidas y no pasaste `--into` ni `--new` (volvé al paso 1). Sale con 65: el archivo se editó a mano y perdió sus marcadores; no se toca: avisale a la persona.

Escribí el fragmento en un archivo temporal fuera del repo y borralo después. No edites `docs/bitacora.html` a mano: el script es lo que garantiza que no se reescribe nada de arriba.

## 4. Avisarle a la persona

Una línea con la sección y el link: `docs/bitacora.html#<slug>`. El archivo es versionado: commitealo en la rama en la que estás trabajando, o decile a la persona que queda para commitear. No abras un PR solo para la bitácora salvo que lo pida.

Tokens del diseño: `scripts/agents/bitacora/barrilete.css`; un proyecto los pisa en su propio .barrilete/bitacora.css, que se lee al crear la página. El detalle está en el doc de la bitácora del kit (docs/agents/bitacora.md, que el modo `--small` no instala).

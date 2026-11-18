# Bitácora del proyecto (`/bitacora`)

`docs/bitacora.html` es la bitácora del proyecto: un archivo por proyecto, versionado en git para que lo tengan todos los integrantes, con una sección por tema (#343). Una persona suma una entrada desde el chat con `/bitacora <tema>` (skill `.claude/skills/bitacora/`): el agente la escribe con el contexto de esa conversación (la idea, sus opciones, qué se descartó y por qué, qué se decidió, qué falta) y `scripts/agents/bitacora_add.py` la inserta. Nada genera entradas solo.

```bash
python3 scripts/agents/bitacora_add.py find --topic "Decidir la ruta"
python3 scripts/agents/bitacora_add.py add --topic "Decidir la ruta" --entry /tmp/entrada.html
python3 scripts/agents/bitacora_add.py add --topic "Decidir las rutas" --into decidir-la-ruta --entry /tmp/entrada.html
python3 scripts/agents/bitacora_add.py -C ../otro-repo add --topic "Release" --new --entry /tmp/entrada.html
```

## Para qué sirve

La bitácora es el lugar donde se **piensan las ideas** del proyecto con el contexto del chat, y donde después queda cómo se llegó a cada una. Una persona pide `/bitacora <tema>` mientras charla una idea y el agente la dibuja en la sección de ese tema: cómo funciona, qué opciones hubo, qué se descartó y por qué, qué se decidió y qué falta. Se escribe con gráficos, poco texto y palabras de persona, sin nombres de archivos ni jerga de código (#361).

| | Bitácora | Retros | PRs |
|---|---|---|---|
| Para quién | personas del equipo | los agentes y `/improve-skills` | quien revisa el cambio |
| Qué cuenta | la idea, sus opciones y por qué se decidió | qué salió bien o mal al trabajar | qué se tocó y cómo se verificó |
| Cómo habla | gráficos y palabras simples | técnico | técnico |

## Cómo se suman las entradas

- **La sección es el tema.** Su slug (minúsculas, sin acentos, con guiones) es su id y su link: `docs/bitacora.html#decidir-la-ruta`. Dos temas con el mismo slug son la misma sección.
- **Solo inserta.** Una sección nueva va al final de `<main>` y su link al final del índice; una entrada va al final de su sección, con la fecha (`--date AAAA-MM-DD`, hoy por defecto). Todo lo que estaba queda byte a byte igual; el test lo comprueba con un diff que solo admite líneas insertadas. Los lugares donde inserta son comentarios HTML (`<!-- bitacora:nav -->`, `<!-- bitacora:main -->`, `<!-- bitacora:end <slug> -->`): si el archivo los perdió (se editó a mano), el script no lo toca y sale con 65.
- **Un nombre parecido se pregunta.** `find` responde `exact <slug>`, `none <slug>` (sale con 0) o una línea `similar <slug>\t<tema>` por cada sección parecida (sale con 3): un slug que contiene al otro entre guiones, o un ratio de `difflib` de 0,8 o más. `add` con una sección parecida y sin `--into <slug>` ni `--new` no escribe y sale con 3; el skill le pregunta a la persona y repite con su respuesta.
- **La entrada es un fragmento HTML** que usa los componentes de abajo, revisado contra una lista permitida (los valores de los atributos, después de decodificar sus entidades; si no, sale con 64 y no toca el archivo). Etiquetas: texto y listas (`p`, `br`, `hr`, `strong`, `b`, `em`, `i`, `u`, `s`, `small`, `mark`, `code`, `pre`, `kbd`, `sub`, `sup`, `span`, `div`, `h3`, `h4`, `ul`, `ol`, `li`, `dl`, `dt`, `dd`, `blockquote`, `abbr`, `time`), links (`a`) y tablas (`table`, `caption`, `thead`, `tbody`, `tfoot`, `tr`, `th`, `td`). Atributos: `class` y `title` en cualquiera, `href` en `a` (solo relativos, `#`, `http(s)` o `mailto`; `//host` y `\\host` son otro sitio y no pasan), `datetime` en `time`, `colspan`, `rowspan` y `scope` en las celdas, y `style` solo en `i` y solo como el ancho de una barra (`--v:70%`). Así, un manejador `on…=` no pasa porque no está entre los atributos y `javascript:` tampoco, porque no es un esquema permitido en `href`; el texto y los valores de los atributos sí pueden nombrarlos (`?only=open` en un link pasa). Además, la entrada no puede tener comentarios, CDATA ni un `<` suelto (escribí `&lt;`, que pasa) y toda etiqueta que abre se tiene que cerrar con su cierre: `<b/>` no la cierra (solo `<br/>` y `<hr/>` se pueden escribir así; `</br>` no cierra nada y no pasa), y la entrada no puede terminar en una etiqueta a medio escribir (`<b`, `<a href="x`). El tema siempre se escribe escapado, como texto, y no puede tomar un id que ya usa la página (`theme-…`, `structure`).
- **CRLF y modo.** Un archivo con fin de línea CRLF (un checkout de Windows) se lee igual y lo que se inserta respeta su fin de línea. Al escribir conserva el modo del archivo (uno nuevo toma el que da el umask).
- **El archivo se crea** la primera vez, con las etiquetas en el idioma de `language` de `.agent-kit.json` (`en` o `es`; sin él, `en`) y el diseño de ese momento. Otras salidas: 64 por un error de uso (también fuera de un repo de git), 1 si no puede leer o escribir.

La página no lleva scripts. El kit no trae un `docs/bitacora.html`: cada proyecto crea el suyo con su primer `/bitacora`.

## Componentes

La página trae los estilos de estas clases; el skill lista su HTML.

| Clase | Para qué |
|---|---|
| `kpis` + `kpi` | números clave, con `ok`, `warn` o `danger` |
| `cards` + `card` | tarjetas por estado (hecho, en curso, te espera a vos) |
| `tbl` | tablas: antes/después, opciones; en un teléfono se desplazan de costado |
| `bars` + `bar` | barras, con el ancho en `style="--v:70%"` |
| `flow` | un flujo de pasos (`<ol>`) |
| `note` | una nota destacada |
| `branch` + `root`, `opts`, `opt` | diagrama con ramas: una pregunta y sus opciones (`opt` con `ok` elegida o `danger` descartada) |
| `map` + `node`, `edge` | mapa de partes: una fila por conexión, «parte → lo que hace → parte» |
| `ok`, `warn`, `danger` | estado: hecho, en curso, espera a una persona o está roto |

## El diseño: tokens

La página tiene la forma del HTML de estado de barrilete: arriba el nombre del proyecto con el dron y la rienda, el índice en una barra clara fija, cada tema como sección numerada (`>_ 01`) y sus entradas sobre la rienda, una debajo de otra, con su fecha. Los colores de marca del dron son fijos; todo lo demás usa solo estos tokens. El diseño de barrilete (`scripts/agents/bitacora/barrilete.css`) les da sus valores por defecto. La página es **siempre clara**: no sigue el modo oscuro del sistema (`color-scheme: light`; lo decidió la persona en #361, antes seguía al sistema).

| Token | Qué es | Valor |
|---|---|---|
| `--bg` | fondo de la página | `#F6F7F9` |
| `--surface` | bloques dentro de una entrada, código | `#E9ECF1` |
| `--card` | entradas | `#FFFFFF` |
| `--ink` | texto | `#14161A` |
| `--muted` | texto secundario | `#5A6270` |
| `--accent` | links y destacados | `#2450E0` |
| `--ok` | hecho | `#17693D` |
| `--warn` | en curso | `#8A5300` |
| `--danger` | te espera a vos, roto | `#B4122B` |
| `--knot` | relleno de los nudos de la rienda, barras en curso y notas; nunca texto | `#FFB020` |
| `--font-display` | títulos | Bricolage Grotesque, después las del sistema |
| `--font-mono` | todo lo demás | JetBrains Mono, después las del sistema |

Cada color de texto llega a WCAG AA (4.5:1) sobre `--bg`, `--surface` y `--card`; el test lo comprueba. Dos valores cambian respecto del HTML de estado de barrilete porque como texto no llegaban: `--accent` (`#2B59FF` daba 4,46 sobre `--surface`) y `--warn` (`#FFB020` daba 1,7; queda `#8A5300`).

Las fuentes vienen de Google Fonts con `display=swap`: sin red, el texto se ve enseguida con las fuentes del sistema.

### El diseño del proyecto

Si el proyecto tiene `.barrilete/bitacora.css`, va después del diseño de barrilete (los dos se copian en la página al crearla) y pisa los tokens que define; lo que no define queda como barrilete. Es un archivo del proyecto: el kit no lo instala y se versiona como cualquier otro.

```css
/* .barrilete/bitacora.css */
:root {
  --accent: #0E9F6E;
  --font-display: "Inter", system-ui, sans-serif;
}
```

Si cambiás colores, revisá el contraste vos: el test solo comprueba el de barrilete.

El diseño se copia en la página cuando se crea, y las entradas nunca lo reescriben: una página que ya existe se queda con el diseño con el que nació. Para darle uno nuevo, cambiá a mano los bloques `<style id="theme-…">` en un PR aparte.

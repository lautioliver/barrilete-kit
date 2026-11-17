# Bitácora de agentes (`bitacora.py`)

`scripts/agents/bitacora.py` arma una página con lo que hizo cada agente en cada cambio: una tarjeta por PR con cada agente que lo tocó (rol y modelo) y lo que reportó en su retro (#339). Lee las retros que `retro.sh` guarda en la rama `agents/retros` y los PRs de `gh pr list`, y escribe `.barrilete/bitacora.html` (ignorado por git, un solo archivo).

```bash
python3 scripts/agents/bitacora.py                      # este repo, diseño de barrilete (+ el del proyecto, si hay)
python3 scripts/agents/bitacora.py -C ../otro-repo      # otro repo
python3 scripts/agents/bitacora.py --theme barrilete    # ignora .barrilete/bitacora.css
python3 scripts/agents/bitacora.py --theme diseño.css   # usa ese archivo en lugar de .barrilete/bitacora.css
python3 scripts/agents/bitacora.py --lang en            # etiquetas en inglés (por defecto: "language" de .agent-kit.json, o en)
```

Imprime `ok: <ruta>` y termina con 0. Un error de uso (un `--theme` que no existe, una opción desconocida) es una línea y 64. Si `gh` falla (sin sesión, sin red), la página sale igual, sin títulos ni estado de los PRs. Sin retros, la página lo dice. Correrlo dos veces con las mismas retros da la misma página.

No se instala en el modo `--small`, que no tiene retros (ahí no se instala `.claude/skills/improve-skills`).

## El contrato de las retros

La bitácora depende de lo que escribe `retro.sh` (`.claude/skills/improve-skills/retro.sh`, plantilla en `retro-template.md`). Si cambia algo de esto, cambiá `bitacora.py` en el mismo PR; `scripts/agents/test-bitacora.sh` escribe una retro con `retro.sh` y falla si la bitácora deja de leerla.

- **Dónde:** `retros/*.md` en la rama `agents/retros`. La de `origin` si el repo tiene ese remoto (la trae antes); si no, la local.
- **Frontmatter** (entre dos líneas `---`), líneas `clave: valor`:
  - `pr`: número del PR (con o sin `#`). Las retros se agrupan por PR.
  - `issue`: número del issue. Sin PR, se agrupan por issue; sin ninguno de los dos, cada retro es su propia tarjeta.
  - `role`: `implementer`, `implementer-light`, `reviewer`, `orchestrator` o `session` (`retro.sh` escribe `session` si falta).
  - `model`: `opus`, `sonnet`, `haiku` o `unknown`.
  - `skill`: `implement-issue`, `review-pr`, `orchestrate` o `improve-skills` (qué hizo el agente).
  - `date`: `AAAA-MM-DD` (la completa `retro.sh`). Los cambios más recientes van primero.
- **Cuerpo:** secciones que empiezan una línea con `**Título:**`. Las cuatro de la plantilla (`Desvíos`, `Decisiones no cubiertas`, `Lo que encontró la revisión`, `Propuesta`, o sus formas en inglés) se traducen al idioma de la página; cualquier otro título se muestra como está. Un cuerpo sin secciones se muestra entero como reporte.

Todo lo de una retro es texto: se escapa, nunca se interpreta como HTML.

## El diseño: tokens

La página usa solo estos tokens. El diseño de barrilete (`scripts/agents/bitacora/barrilete.css`) les da sus valores por defecto, para modo claro y oscuro (sigue al sistema con `prefers-color-scheme`).

| Token | Qué es | Claro | Oscuro |
|---|---|---|---|
| `--bg` | fondo de la página | `#F6F7F9` | `#121418` |
| `--surface` | bloques dentro de una tarjeta, código | `#E9ECF1` | `#1C1F26` |
| `--card` | tarjetas | `#FFFFFF` | `#23262E` |
| `--ink` | texto | `#14161A` | `#ECEEF2` |
| `--muted` | texto secundario | `#5A6270` | `#A3AAB6` |
| `--accent` | links y etiquetas de agente | `#2450E0` | `#8FB0FF` |
| `--ok` | mergeado | `#17693D` | `#5FD39A` |
| `--warn` | abierto | `#8A5300` | `#FFB020` |
| `--danger` | cerrado | `#B4122B` | `#FF8A96` |
| `--font-display` | títulos | Bricolage Grotesque, después las del sistema | |
| `--font-mono` | todo lo demás | JetBrains Mono, después las del sistema | |

Cada color de texto llega a WCAG AA (4.5:1) sobre `--bg`, `--surface` y `--card` en los dos modos; el test lo comprueba. Dos valores del modo claro cambian respecto del HTML de estado de barrilete porque como texto no llegaban: `--accent` (`#2B59FF` daba 4,46 sobre `--surface`) y `--warn` (`#FFB020` daba 1,7; queda como el del modo oscuro).

Las fuentes vienen de Google Fonts con `display=swap`: sin red, el texto se ve enseguida con las fuentes del sistema.

### El diseño del proyecto

Si el proyecto tiene `.barrilete/bitacora.css`, va después del diseño de barrilete y pisa los tokens que define; lo que no define queda como barrilete. Es un archivo del proyecto: el kit no lo instala y se versiona como cualquier otro.

```css
/* .barrilete/bitacora.css */
:root {
  --accent: #0E9F6E;
  --font-display: "Inter", system-ui, sans-serif;
}
@media (prefers-color-scheme: dark) {
  :root { --accent: #6EE7B7; }
}
```

Un token definido solo en `:root` vale para los dos modos (un `:root` posterior le gana al bloque oscuro de barrilete): para darle al modo oscuro su propio valor, definilo también en el bloque `@media`, como en el ejemplo. Si cambiás colores, revisá el contraste vos: el test solo comprueba el de barrilete.

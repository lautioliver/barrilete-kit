# Brand of agent-kit-template

Identity of the template, not of the projects that come out of it: `init-template.sh` deletes this folder and the brand block of the README.

## Idea

**Barrilete** is a drone tied to a leash with two knots. It flies and explores on its own, but the handle, and the last word, stay in your hand.

- **Tagline:** "Los agentes vuelan. Vos tenés la rienda." (the artwork keeps the Spanish text; in English: "Agents fly. You hold the leash."). In the terminal: `>_ los agentes vuelan, vos tenés la rienda`.
- **The two knots** are the two control points that always stay in people's hands: approving the plan and merging (plan ● — implement · review — ● merge).
- **Stamp:** `SALTA DEV`, white on red with a bottom border in ink.

![Barrilete, the drone on a leash](drone-on-leash.svg)

## Icon

| 128 px | 64 px | 32 px | Dark background |
|---|---|---|---|
| ![](barrilete.svg) | ![](barrilete-64.svg) | ![](barrilete-32.svg) | ![](barrilete-dark.svg) |

Each size has its own drawing: at 64 px the propellers and eyes are thickened, and at 32 px the light face disappears and only the eyes and a large mouth remain over the ink silhouette. Don't scale the 128 one down to 32.

## States

For issues, PRs and the README.

| State | When | File |
|---|---|---|
| ![](states/working.svg) working | `/implement-issue` in progress | [`states/working.svg`](states/working.svg) |
| ![](states/planning.svg) planning | `/plan-feature` in progress | [`states/planning.svg`](states/planning.svg) |
| ![](states/blocked.svg) blocked | label `status:blocked` | [`states/blocked.svg`](states/blocked.svg) |
| ![](states/pr-ready.svg) PR ready | waiting for your merge (the mouth turns amber) | [`states/pr-ready.svg`](states/pr-ready.svg) |

## Palette

| Role | Color |
|---|---|
| Ink (text, propellers, visor) | `#14161A` |
| Grey (secondary text) | `#5A6270` |
| Background | `#F6F7F9` |
| Surface (body, panels) | `#E9ECF1` |
| White | `#FFFFFF` |
| Red (leash, mouth, stamp) | `#B4122B` |
| Amber (knots, PR ready) | `#FFB020` |
| Eyes | `#8FB0FF` |
| Blue (`>_` prompt) | `#2B59FF` |
| Blocked (eyes crossed) | `#FF8A96` |

## Typography

- **Bricolage Grotesque** 800 for titles and 600 for the tagline.
- **JetBrains Mono** 400 and 500 for everything else (text, labels, stamp).

Both are from Google Fonts (OFL license).

## Social preview

![Social preview](social-preview.png)

[`social-preview.png`](social-preview.png) (1280×640) is uploaded by hand on GitHub: **Settings → General → Social preview**. The source is [`social-preview.html`](social-preview.html); if the text changes, regenerate the PNG with the command in its header.

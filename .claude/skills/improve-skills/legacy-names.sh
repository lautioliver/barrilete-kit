#!/usr/bin/env bash
# Table of the 0.9 (Spanish) values of `skill:` and `rol:` in the retros, and their new names.
# One place for retro.sh and signals.sh: old retros (saved before the renames) are normalized
# when they are read, so the history is not split into two groups. Sourced, not run.
# Usage: normalize_legacy_names < text   (rewrites the `skill:` and `rol:` lines of the frontmatter)
normalize_legacy_names() {
  sed -E \
    -e 's/^skill:[[:space:]]*orquestar[[:space:]]*$/skill: orchestrate/' \
    -e 's/^skill:[[:space:]]*mejorar-skills[[:space:]]*$/skill: improve-skills/' \
    -e 's/^rol:[[:space:]]*implementador-liviano[[:space:]]*$/rol: implementer-light/' \
    -e 's/^rol:[[:space:]]*implementador[[:space:]]*$/rol: implementer/' \
    -e 's/^rol:[[:space:]]*revisor[[:space:]]*$/rol: reviewer/'
}

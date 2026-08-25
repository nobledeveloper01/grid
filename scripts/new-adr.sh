#!/usr/bin/env bash
#
# Scaffolds the next ADR, numbered for you so two decisions never collide.
#
#   scripts/new-adr.sh "Readings are immutable facts"
set -euo pipefail
cd "$(dirname "$0")/.."

title="${*:-}"
if [ -z "$title" ]; then
  printf 'usage: scripts/new-adr.sh "the decision, as a sentence"\n' >&2
  exit 64
fi

mkdir -p docs/adr
last=$(ls docs/adr/[0-9]*.md 2>/dev/null | sed 's#.*/##' | cut -d- -f1 | sort -n | tail -1)
next=$(printf '%04d' $(( 10#${last:-0} + 1 )))

slug=$(printf '%s' "$title" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
  | cut -c1-60)

path="docs/adr/${next}-${slug}.md"
[ -e "$path" ] && { printf 'already exists: %s\n' "$path" >&2; exit 1; }

cat > "$path" <<EOF
# ADR-${next} — ${title}

**Status:** proposed
**Date:** $(date +%Y-%m-%d)

## Context

<!--
What forced this decision. Include the obvious approach — the one most people
would reach for — and say plainly why it does not work here. An ADR that only
describes the chosen path is a press release; the value is in the alternative
that was rejected and the reason.
-->

## Decision

<!-- What we are doing. Present tense, specific enough to check code against. -->

## Consequences

<!--
What this costs, not only what it buys. What becomes harder. What a future
reader might reasonably want to reverse, and what they would have to deal with
if they did.
-->
EOF

printf '%s\n' "$path"

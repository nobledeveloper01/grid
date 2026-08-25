#!/usr/bin/env bash
#
# Appends a session entry to docs/JOURNAL.md.
#
# The journal answers a question the changelog cannot: not "what shipped" but
# "what did we learn, and what surprised us". A month later the surprises are
# the part nobody remembers and everybody needs.
#
#   scripts/journal.sh "Capture and forecast"
set -euo pipefail
cd "$(dirname "$0")/.."

title="${*:-}"
if [ -z "$title" ]; then
  printf 'usage: scripts/journal.sh "what this session was about"\n' >&2
  exit 64
fi

phase=$(tr -d '[:space:]' < PHASE 2>/dev/null || echo '?')
today=$(date +%Y-%m-%d)

# Start the entry from facts rather than from memory: what actually changed
# since the journal was last written.
since=$(git log -1 --format=%H -- docs/JOURNAL.md 2>/dev/null || true)
stat_line=""
commit_line=""
if [ -n "$since" ]; then
  changed=$(git diff --shortstat "$since"..HEAD 2>/dev/null | sed 's/^ *//' || true)
  n=$(git log --oneline "$since"..HEAD 2>/dev/null | wc -l | tr -d ' ' || echo 0)
  [ -n "$changed" ] && stat_line=" $changed."
  [ "${n:-0}" != "0" ] && commit_line=" ${n} commits."
fi

entry=$(mktemp)
{
  printf '\n## %s — %s\n\n' "$today" "$title"
  printf '**Phase %s.**%s%s\n\n' "$phase" "$commit_line" "$stat_line"
  printf '### What we built\n\n-\n\n'
  printf '### What we decided\n\n'
  printf '<!-- Anything non-obvious wants an ADR: make adr T="the decision" -->\n-\n\n'
  printf '### What surprised us\n\n'
  printf '%s\n' '<!--'
  printf 'The most valuable section. A tool that behaved differently than its docs, a\n'
  printf 'test that caught something a review would not have, an assumption that turned\n'
  printf 'out wrong. Write down the ones that cost time — they are worth an hour of\n'
  printf 'somebody else later.\n'
  printf '%s\n-\n\n' '-->'
  printf '### Where we stopped\n\n-\n'
} > "$entry"

# Splice in after the header rule, so newest is first.
out=$(mktemp)
awk -v f="$entry" '
  BEGIN { done = 0 }
  { print }
  !done && /^---$/ {
    while ((getline line < f) > 0) print line
    close(f)
    done = 1
  }
' docs/JOURNAL.md > "$out"

mv "$out" docs/JOURNAL.md
rm -f "$entry"

printf 'added a %s entry to docs/JOURNAL.md — fill it in\n' "$today"

#!/usr/bin/env bash
#
# Captures a simulator screen into docs/screenshots/.
#
# Screenshots are not decoration in a mobile README — they are the only part of
# the documentation that shows what the thing actually looks like, and prose
# describing a screen is a picture nobody can see. They are also the first part
# to rot, so this exists to make retaking the whole set cheap rather than a
# chore somebody skips.
#
#   GRID_SIM=<udid> scripts/screenshot.sh 01-home
#
# Width is halved to 540px — sharp at the ~260px the README renders them at —
# and the result is quantised to a 256-colour palette. A flat dark UI has very
# few distinct colours, so that is visually lossless here and cuts each file
# from ~550 KB to ~90 KB. Ten screenshots then cost about a megabyte rather
# than five, which is the difference between documentation and a payload.
set -euo pipefail
cd "$(dirname "$0")/.."

name="${1:-}"
if [ -z "$name" ]; then
  printf 'usage: scripts/screenshot.sh <name>\n' >&2
  exit 64
fi

device="${GRID_SIM:-booted}"
out="docs/screenshots/${name}.png"

xcrun simctl io "$device" screenshot --type=png "$out" >/dev/null 2>&1
sips --resampleWidth 540 "$out" --out "$out" >/dev/null

python3 - "$out" <<'PY'
import sys
from PIL import Image

path = sys.argv[1]
img = Image.open(path).convert('RGB')
img.quantize(colors=256, method=Image.MEDIANCUT).save(path, optimize=True)
PY

printf '%s (%s)\n' "$out" "$(du -h "$out" | cut -f1)"

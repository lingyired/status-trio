#!/usr/bin/env bash
# Measure menu-bar icon alignment (#30) from a REAL Agent Desktop screenshot.
#
# It binds to the branch's running development instance (launched through
# scripts/launch-computer-use.sh), reads the status item's Accessibility frame,
# captures the display with agent-desktop, and runs the pixel analyser.
#
# Read-only: it takes a screenshot and reads AX bounds; it never clicks, focuses
# the app, or moves the pointer.
#
# Usage:
#   bash scripts/run-menubar-alignment-check.sh [--screen N] [--scale S] [--icon-size PT]
#
# Run it once per display the user cares about. On a mixed 1x/2x setup pass
# --screen for the display whose menu bar holds the item and --scale for its
# backing scale; auto-detection uses the main screen.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCREEN="0"
SCALE=""
ICON_SIZE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --screen) SCREEN="$2"; shift 2 ;;
        --scale) SCALE="$2"; shift 2 ;;
        --icon-size) ICON_SIZE="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

BRANCH="$(git -C "$ROOT" branch --show-current)"
if [[ -z "$BRANCH" || "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
    echo "Error: run from a named development branch in the isolated worktree." >&2
    exit 2
fi
SUFFIX="$(printf '%s' "$BRANCH" | sed -E 's#^codex/##' | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
BUNDLE_ID="com.lingsmbp.StatusTrio.dev.$SUFFIX"
APP="$ROOT/dist/StatusTrio.app"

PID="$(pgrep -f "$APP/Contents/MacOS/StatusTrio" | head -1 || true)"
if [[ -z "$PID" ]]; then
    echo "Error: no running development instance for $BUNDLE_ID." >&2
    echo "Launch it first: bash scripts/launch-computer-use.sh" >&2
    exit 1
fi

FRAME_JSON="$(swift "$ROOT/scripts/menubar-item-frame.swift" "$PID")"
read -r AX_X AX_Y AX_W AX_H AUTO_SCALE < <(python3 -c "
import json,sys
d=json.loads('''$FRAME_JSON''')
print(d['x'], d['y'], d['w'], d['h'], d['mainScale'])
")
[[ -z "$SCALE" ]] && SCALE="$AUTO_SCALE"

if [[ -z "$ICON_SIZE" ]]; then
    ICON_SIZE="$(defaults read "$BUNDLE_ID" menuBarIconSize 2>/dev/null || echo 24)"
fi

# Physical-pixel rect (exclusive right/bottom) for the analyser.
read -r BX0 BY0 BX1 BY1 < <(python3 -c "
x,y,w,h,s=$AX_X,$AX_Y,$AX_W,$AX_H,$SCALE
import math
print(round(x*s), round(y*s), round((x+w)*s), round((y+h)*s))
")

STAMP="$(date +%Y%m%d-%H%M%S)"
OUTDIR="$ROOT/artifacts/icon-alignment/run-$STAMP"
mkdir -p "$OUTDIR"
SHOT="$OUTDIR/screen.png"

agent-desktop screenshot --screen "$SCREEN" "$SHOT" >/dev/null

python3 "$ROOT/scripts/test-menubar-icon-alignment.py" \
    --screenshot "$SHOT" \
    --button-rect "$BX0,$BY0,$BX1,$BY1" \
    --scale "$SCALE" \
    --icon-size "$ICON_SIZE" \
    --out-json "$OUTDIR/measure.json" \
    --out-prefix "$OUTDIR/icon"

echo "display scale : $SCALE"
echo "status frame  : x=$AX_X y=$AX_Y w=$AX_W h=$AX_H (screen $SCREEN)"
echo "artifacts     : $OUTDIR"

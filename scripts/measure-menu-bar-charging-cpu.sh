#!/usr/bin/env bash
#
# Samples the menu-bar charging animation's CPU cost on this machine.
#
# Usage:
#   scripts/measure-menu-bar-charging-cpu.sh on   /tmp/run-on-1
#   scripts/measure-menu-bar-charging-cpu.sh off  /tmp/run-off-1
#
# Environment:
#   APP_BUNDLE       path to the .app under test (default: this worktree's dist)
#   BUNDLE_ID        defaults domain to seed (default: read from the bundle)
#   SAMPLE_SECONDS   number of 1-second samples (default: 60)
#   SETTLE_SECONDS   warm-up before sampling (default: 15)
#   EXTRA_PIDS       extra processes to sample, for example "$(pgrep -x Dock)"
#
# The script launches the app itself, so both variants of a pair run under the
# same conditions: same build, settings window closed, Dock static. `on` leaves
# the charging animation enabled; `off` disables only that preference, so both
# runs feed the icon the same synthetic charging state.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-}"
OUTPUT_PREFIX="${2:-}"

case "$MODE" in
    on|off) ;;
    *)
        echo "Usage: $0 <on|off> <output-prefix>" >&2
        exit 2
        ;;
esac

if [[ -z "$OUTPUT_PREFIX" ]]; then
    echo "Usage: $0 <on|off> <output-prefix>" >&2
    exit 2
fi

SAMPLE_SECONDS="${SAMPLE_SECONDS:-60}"
SETTLE_SECONDS="${SETTLE_SECONDS:-15}"
APP_BUNDLE="${APP_BUNDLE:-$ROOT/dist/StatusTrio.app}"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "App bundle not found: $APP_BUNDLE" >&2
    exit 1
fi

EXECUTABLE="$APP_BUNDLE/Contents/MacOS/StatusTrio"
if [[ ! -x "$EXECUTABLE" ]]; then
    echo "App executable not found: $EXECUTABLE" >&2
    exit 1
fi

BUNDLE_ID="${BUNDLE_ID:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")}"

case "$MODE" in
    on) SHOWS_MENU_BAR_CHARGING_EFFECT=true ;;
    off) SHOWS_MENU_BAR_CHARGING_EFFECT=false ;;
esac

# Seed the preference before launch; the app reads it during startup.
defaults write "$BUNDLE_ID" appIconPlacement -string menuBar
defaults write "$BUNDLE_ID" showsMenuBarChargingEffect -bool "$SHOWS_MENU_BAR_CHARGING_EFFECT"
defaults write "$BUNDLE_ID" showsDockChargingEffect -bool false

APP_PID=""
cleanup() {
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "mode=$MODE bundle=$BUNDLE_ID app=$APP_BUNDLE"
echo "showsMenuBarChargingEffect=$SHOWS_MENU_BAR_CHARGING_EFFECT showsDockChargingEffect=false settle=${SETTLE_SECONDS}s samples=${SAMPLE_SECONDS}s"

STATUS_TRIO_FORCE_CHARGING_INPUT=1 "$EXECUTABLE" >"$OUTPUT_PREFIX.app.log" 2>&1 &
APP_PID=$!

sleep "$SETTLE_SECONDS"

if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "The app exited during the settle window; see $OUTPUT_PREFIX.app.log" >&2
    exit 1
fi

top -l "$((SAMPLE_SECONDS + 1))" -s 1 -pid "$APP_PID" -stats pid,command,cpu,mem \
    >"$OUTPUT_PREFIX.top.txt"

for extra_pid in ${EXTRA_PIDS:-}; do
    top -l "$((SAMPLE_SECONDS + 1))" -s 1 -pid "$extra_pid" -stats pid,command,cpu,mem \
        >"$OUTPUT_PREFIX.extra-$extra_pid.top.txt"
done

python3 - "$MODE" "$APP_PID" "$OUTPUT_PREFIX.top.txt" "$OUTPUT_PREFIX.summary.txt" <<'PY'
import re
import statistics
import sys

mode, pid, samples_path, summary_path = sys.argv[1:5]
rows = []
with open(samples_path, encoding="utf-8", errors="replace") as handle:
    for line in handle:
        match = re.match(r"^\s*(\d+)\s+(\S+)\s+([\d.]+)\s+(\d+)([KMG]?)[+-]?\s*$", line)
        if match and match.group(1) == pid:
            rows.append((float(match.group(3)), match.group(4), match.group(5)))

if not rows:
    raise SystemExit(f"no samples for pid {pid} in {samples_path}")

CPU_INDEX = {"": 1, "K": 1024, "M": 1024 ** 2, "G": 1024 ** 3}
cpu = [row[0] for row in rows]
memory = [int(row[1]) * CPU_INDEX[row[2]] for row in rows]
summary = [
    f"mode={mode}",
    f"samples={len(cpu)}",
    f"cpu_mean={statistics.fmean(cpu):.2f}",
    f"cpu_peak={max(cpu):.2f}",
    f"cpu_median={statistics.median(cpu):.2f}",
    f"rss_min_mb={min(memory) / 1048576:.1f}",
    f"rss_max_mb={max(memory) / 1048576:.1f}",
]
text = "\n".join(summary) + "\n"
with open(summary_path, "w", encoding="utf-8") as handle:
    handle.write(text)
print(text, end="")
PY

echo "raw=$OUTPUT_PREFIX.top.txt summary=$OUTPUT_PREFIX.summary.txt"

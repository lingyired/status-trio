#!/usr/bin/env bash
#
# Samples the Dock charging animation's CPU cost on this machine.
#
# Usage:
#   scripts/measure-dock-charging-cpu.sh dock on    /tmp/dock-on-1
#   scripts/measure-dock-charging-cpu.sh dock off   /tmp/dock-off-1
#   scripts/measure-dock-charging-cpu.sh menuBar on /tmp/menu-on-1
#
# Environment:
#   APP_BUNDLE       path to the .app under test (default: this worktree's dist)
#   BUNDLE_ID        defaults domain to seed (default: read from the bundle)
#   SAMPLE_SECONDS   number of 1-second samples (default: 60)
#   SETTLE_SECONDS   warm-up before sampling (default: 15)
#   EXTRA_PIDS       extra processes to sample (default: Dock and WindowServer)
#   MEMORY_OUTPUT    optional JSON path; samples app footprint concurrently
#                    with CPU and finishes vmmap while the app is still alive
#   DOCK_RENDERER    `applicationIcon` selects the A/B prototype that swaps
#                    `applicationIconImage` frames instead of animating the
#                    tile's content view (development bundles only)
#
# The script launches the app itself, so both variants of a pair run under the
# same conditions: same build, same placement, settings window closed. `on`
# leaves the charging animation enabled; `off` disables only that preference,
# and both runs feed the icon the same synthetic charging state.
#
# Dock and WindowServer are sampled as well: the Dock animation asks the Dock to
# redraw a tile 20 times a second, so an app-only sample would hide the cost the
# animation moves onto the Dock and the compositor.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PLACEMENT="${1:-}"
MODE="${2:-}"
OUTPUT_PREFIX="${3:-}"

case "$PLACEMENT" in
    dock|menuBar|both) ;;
    *)
        echo "Usage: $0 <dock|menuBar|both> <on|off> <output-prefix>" >&2
        exit 2
        ;;
esac

case "$MODE" in
    on|off) ;;
    *)
        echo "Usage: $0 <dock|menuBar|both> <on|off> <output-prefix>" >&2
        exit 2
        ;;
esac

if [[ -z "$OUTPUT_PREFIX" ]]; then
    echo "Usage: $0 <dock|menuBar|both> <on|off> <output-prefix>" >&2
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

if pgrep -f "$EXECUTABLE" >/dev/null 2>&1; then
    echo "An instance of this build is already running; the single-instance guard would abort the sample." >&2
    echo "Quit it before running a measurement." >&2
    exit 1
fi

BUNDLE_ID="${BUNDLE_ID:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")}"

case "$PLACEMENT:$MODE" in
    dock:on|both:on)
        SHOWS_DOCK_CHARGING_EFFECT=true
        ;;
    *) SHOWS_DOCK_CHARGING_EFFECT=false ;;
esac
case "$PLACEMENT:$MODE" in
    menuBar:on|both:on)
        SHOWS_MENU_BAR_CHARGING_EFFECT=true
        ;;
    *) SHOWS_MENU_BAR_CHARGING_EFFECT=false ;;
esac

# Seed the preferences before launch; the app reads them during startup.
defaults write "$BUNDLE_ID" appIconPlacement -string "$PLACEMENT"
defaults write "$BUNDLE_ID" showsMenuBarChargingEffect -bool "$SHOWS_MENU_BAR_CHARGING_EFFECT"
defaults write "$BUNDLE_ID" showsDockChargingEffect -bool "$SHOWS_DOCK_CHARGING_EFFECT"

APP_PID=""
SAMPLE_PIDS=()
cleanup() {
    for sample_pid in "${SAMPLE_PIDS[@]:-}"; do
        [[ -n "$sample_pid" ]] || continue
        kill -0 "$sample_pid" 2>/dev/null \
            && kill -TERM "$sample_pid" 2>/dev/null \
            || true
    done
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        # Give the app a chance to run `applicationWillTerminate` so a
        # measurement run never leaves a stale single-instance lock behind.
        kill -TERM "$APP_PID" 2>/dev/null || true
        for _ in {1..20}; do
            kill -0 "$APP_PID" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if [[ -z "${EXTRA_PIDS:-}" ]]; then
    EXTRA_PIDS="$(pgrep -x Dock || true) $(pgrep -x WindowServer || true)"
fi

echo "placement=$PLACEMENT mode=$MODE bundle=$BUNDLE_ID app=$APP_BUNDLE"
echo "showsMenuBarChargingEffect=$SHOWS_MENU_BAR_CHARGING_EFFECT showsDockChargingEffect=$SHOWS_DOCK_CHARGING_EFFECT settle=${SETTLE_SECONDS}s samples=${SAMPLE_SECONDS}s"
echo "extra_pids=${EXTRA_PIDS:-none} dock_renderer=${DOCK_RENDERER:-tile}"

append_to_summary_header() {
    printf '%s\n' "dock_renderer=${DOCK_RENDERER:-tile}" >>"$OUTPUT_PREFIX.summary.txt"
}

APP_ENVIRONMENT=(STATUS_TRIO_FORCE_CHARGING_INPUT=1)
if [[ -n "${DOCK_RENDERER:-}" ]]; then
    APP_ENVIRONMENT+=("STATUS_TRIO_DOCK_ANIMATION_RENDERER=$DOCK_RENDERER")
fi

env "${APP_ENVIRONMENT[@]}" "$EXECUTABLE" >"$OUTPUT_PREFIX.app.log" 2>&1 &
APP_PID=$!

sleep "$SETTLE_SECONDS"

if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "The app exited during the settle window; see $OUTPUT_PREFIX.app.log" >&2
    exit 1
fi

sample_top() {
    local pid="$1" path="$2"
    top -l "$((SAMPLE_SECONDS + 1))" -s 1 -pid "$pid" -stats pid,command,cpu,mem >"$path"
}

# Confirm the animation actually ran. `sample` appends to `-file`, and the
# process has to be alive for the full window; a shorter sample would miss the
# steady pump and make a real animation look like a zero-cost no-op.
if [[ "$MODE" == "on" ]]; then
    /usr/bin/sample "$APP_PID" 2 -mayDie -file "$OUTPUT_PREFIX.calls.txt" >/dev/null 2>&1 || true
fi
if [[ "$MODE" == "on" ]] && ! grep -q "ChargingEffectClock.start" "$OUTPUT_PREFIX.calls.txt" 2>/dev/null; then
    echo "The animation clock did not run; refusing to report a zero-cost 'on' measurement." >&2
    exit 1
fi

# Start footprint sampling only after the clock gate has passed. The exact
# executable check protects the shared app PID before handing it to libproc.
if [[ -n "${MEMORY_OUTPUT:-}" ]]; then
    ACTUAL_EXECUTABLE="$(ps -p "$APP_PID" -o comm= 2>/dev/null || true)"
    if [[ "$ACTUAL_EXECUTABLE" != "$EXECUTABLE" ]]; then
        echo "The app PID no longer identifies the expected executable: $ACTUAL_EXECUTABLE" >&2
        exit 1
    fi
    python3 "$ROOT/scripts/measure-memory.py" \
        --pid "$APP_PID" --seconds "$SAMPLE_SECONDS" --output "$MEMORY_OUTPUT" &
    SAMPLE_PIDS+=("$!")
fi

# Sample every process at once: serial `top` runs would drift apart and turn the
# app, Dock and WindowServer numbers into three different windows in time.
sample_top "$APP_PID" "$OUTPUT_PREFIX.app.top.txt" &
SAMPLE_PIDS+=("$!")
for extra_pid in ${EXTRA_PIDS:-}; do
    sample_top "$extra_pid" "$OUTPUT_PREFIX.extra-$extra_pid.top.txt" &
    SAMPLE_PIDS+=($!)
done

sample_failure=0
pending_sample_pids=("${SAMPLE_PIDS[@]}")
for ((sample_index = 0; sample_index < ${#pending_sample_pids[@]}; sample_index++)); do
    sample_pid="${pending_sample_pids[$sample_index]}"
    if ! wait "$sample_pid"; then
        echo "Sample job failed: PID $sample_pid" >&2
        sample_failure=1
    fi
    SAMPLE_PIDS=("${pending_sample_pids[@]:sample_index+1}")
done
SAMPLE_PIDS=()
if (( sample_failure != 0 )); then
    exit 1
fi

python3 - "$PLACEMENT" "$MODE" "$APP_PID" "$OUTPUT_PREFIX" "${EXTRA_PIDS:-}" <<'PY'
import os
import re
import statistics
import sys

placement, mode, app_pid, prefix, extra_pids = sys.argv[1:6]
extra_pids = extra_pids.split() if extra_pids else []


def rows(path):
    if not os.path.exists(path):
        return []
    collected = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = re.match(r"^\s*(\d+)\s+(\S+)\s+([\d.]+)\s+(\d+)([KMG]?)[+-]?\s*$", line)
            if match:
                collected.append((match.group(2), float(match.group(3))))
    return collected


def stats(samples):
    values = [cpu for _, cpu in samples]
    if not values:
        return None
    return {
        "command": samples[0][0],
        "samples": len(values),
        "cpu_mean": statistics.fmean(values),
        "cpu_peak": max(values),
        "cpu_median": statistics.median(values),
    }


summary = [f"placement={placement}", f"mode={mode}"]

app = stats(rows(f"{prefix}.app.top.txt"))
if app is None:
    raise SystemExit(f"no samples for the app in {prefix}.app.top.txt")
summary += [
    f"app_command={app['command']}",
    f"app_samples={app['samples']}",
    f"app_cpu_mean={app['cpu_mean']:.2f}",
    f"app_cpu_peak={app['cpu_peak']:.2f}",
    f"app_cpu_median={app['cpu_median']:.2f}",
]

combined = app["cpu_mean"]
for extra_pid in extra_pids:
    extra = stats(rows(f"{prefix}.extra-{extra_pid}.top.txt"))
    if extra is None:
        continue
    summary += [
        f"pid{extra_pid}_command={extra['command']}",
        f"pid{extra_pid}_cpu_mean={extra['cpu_mean']:.2f}",
        f"pid{extra_pid}_cpu_peak={extra['cpu_peak']:.2f}",
    ]
    combined += extra["cpu_mean"]

summary.append(f"combined_cpu_mean={combined:.2f}")
text = "\n".join(summary) + "\n"
with open(f"{prefix}.summary.txt", "w", encoding="utf-8") as handle:
    handle.write(text)
print(text, end="")
PY

append_to_summary_header

echo "raw=$OUTPUT_PREFIX.app.top.txt summary=$OUTPUT_PREFIX.summary.txt"

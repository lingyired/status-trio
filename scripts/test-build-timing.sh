#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioBuildTiming.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
rc=0
BUILD_TIMING_FILE="$WORK/timings.tsv" bash -euo pipefail -c '
    source "$1/scripts/build-timing.sh"
    trap '"'"'build_timing_finish "$?"'"'"' EXIT
    build_phase compile
    build_phase codesign
    exit 17
' bash "$ROOT" >"$WORK/log" 2>&1 || rc=$?
[[ "$rc" == 17 ]] || { cat "$WORK/log"; exit 1; }
python3 - "$WORK/timings.tsv" <<'PY'
import sys
rows = [line.split("\t") for line in open(sys.argv[1]).read().splitlines()]
assert [row[0] for row in rows] == ["compile", "codesign"], rows
assert [row[2] for row in rows] == ["0", "17"], rows
assert all(float(row[1]) >= 0 for row in rows), rows
PY
GITHUB_STEP_SUMMARY="$WORK/summary.md" python3 "$ROOT/scripts/ci-diagnostics.py" \
    timings "$WORK/timings.tsv"
grep -Fq "codesign (signing)" "$WORK/summary.md"
rc=0
BUILD_TIMING_FILE="$WORK/missing-directory/timings.tsv" bash -euo pipefail -c '
    source "$1/scripts/build-timing.sh"
    trap '"'"'build_timing_finish "$?"'"'"' EXIT
    build_phase compile
    exit 31
' bash "$ROOT" >"$WORK/unwritable.log" 2>&1 || rc=$?
[[ "$rc" == 31 ]] || { cat "$WORK/unwritable.log"; echo "FAIL: timing write changed exit to $rc"; exit 1; }
printf 'truncated\n' >> "$WORK/timings.tsv"
GITHUB_STEP_SUMMARY="$WORK/partial-summary.md" python3 "$ROOT/scripts/ci-diagnostics.py" \
    timings "$WORK/timings.tsv"
grep -Fq 'Unreadable timing row' "$WORK/partial-summary.md"
grep -Fq 'codesign (signing)' "$WORK/partial-summary.md"
python3 - "$ROOT/scripts/build-app.sh" "$WORK/icon-cleanup.sh" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
cleanup = next(line for line in source.splitlines() if line.startswith("trap ") and "ICON_WORK_DIR" in line)
Path(sys.argv[2]).write_text(
    'source "$1/scripts/build-timing.sh"\nICON_WORK_DIR="$2"\n'
    'mkdir -p "$ICON_WORK_DIR"\nbuild_phase signed-bundle-contracts\n'
    + cleanup + '\nexit 37\n'
)
PY
rc=0
BUILD_TIMING_FILE="$WORK/icon.tsv" bash -euo pipefail \
    "$WORK/icon-cleanup.sh" "$ROOT" "$WORK/icon-work" >"$WORK/icon.log" 2>&1 || rc=$?
[[ "$rc" == 37 && ! -d "$WORK/icon-work" ]] || exit 1
[[ -f "$WORK/icon.tsv" ]] || { echo "FAIL: icon cleanup replaced the build timing trap"; exit 1; }
grep -Fq 'signed-bundle-contracts' "$WORK/icon.tsv"
echo "Build timings preserve phase order and original failure status"

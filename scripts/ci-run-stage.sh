#!/usr/bin/env bash
# Capture verify output without replacing the command's failure with tee's.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="${1:?stage is required}"
shift
[[ "$STAGE" =~ ^[a-zA-Z0-9_-]+$ && "$#" -gt 0 ]] || exit 2
LOG_DIR="${CI_LOG_DIR:-$ROOT/.build/ci-logs}"
mkdir -p "$LOG_DIR"
START="$(python3 -c 'import time; print(time.monotonic())')"
set +e
"$@" 2>&1 | tee "$LOG_DIR/$STAGE.log"
RESULTS=("${PIPESTATUS[@]}")
set -e
RESULT="${RESULTS[0]}"
if [[ "$RESULT" == 0 && "${RESULTS[1]}" != 0 ]]; then
    RESULT="${RESULTS[1]}"
fi
# Diagnostics must never turn the original failing command into success.
python3 "$ROOT/scripts/ci-diagnostics.py" record \
    "$STAGE" "$RESULT" "$START" "$LOG_DIR" || {
        [[ "$RESULT" != 0 ]] || RESULT=1
    }
exit "$RESULT"

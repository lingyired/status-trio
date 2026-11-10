#!/usr/bin/env bash
# Standalone, explicitly invoked PowerUI research. Never linked into Status Trio.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-}"
if [[ $# -ne 1 || ( "$MODE" != "--inspect" && "$MODE" != "--self-test" ) ]]; then
    echo "Usage: bash scripts/probe-charge-to-full-now.sh <--inspect|--self-test>" >&2
    echo "--inspect reads PowerUI metadata/state; --self-test uses fake classes without loading PowerUI." >&2
    echo "No charging write operation is implemented." >&2
    exit 2
fi

PROBE_DIR="$ROOT/.build/charge-to-full-now-poc"
mkdir -p "$PROBE_DIR"
if [[ "$MODE" == "--self-test" ]]; then
    xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
        -mmacosx-version-min=13.0 \
        "$ROOT/scripts/poc/charge-to-full-now-readonly-tests.m" -o "$PROBE_DIR/safety-tests"
    exec "$PROBE_DIR/safety-tests"
fi

xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation -framework IOKit \
    -mmacosx-version-min=13.0 \
    "$ROOT/scripts/poc/charge-to-full-now-readonly.m" -o "$PROBE_DIR/readonly"

# Bound synchronous private XPC reads to a short-lived child, never the app's main thread.
python3 - "$PROBE_DIR/readonly" <<'PY'
import subprocess
import sys

try:
    result = subprocess.run([sys.argv[1], "--inspect"], timeout=20)
except subprocess.TimeoutExpired:
    print("Read-only PowerUI probe timed out after 20 seconds; integration remains BLOCKED.", file=sys.stderr)
    sys.exit(124)
sys.exit(result.returncode)
PY

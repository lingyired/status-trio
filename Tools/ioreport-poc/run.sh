#!/usr/bin/env bash
# Build and run the IOReport power POC. Development tool only — not part of
# Package.swift, never bundled into the app.
#
#   bash run.sh groups
#   bash run.sh list --group "Energy Model"
#   bash run.sh sample --window 5 --json
#   bash run.sh bench --window 6
#   bash run.sh selftest
#   bash run.sh experiments          # full controlled batch -> /tmp/ioreport-poc
#
# Requires only Xcode command line tools. No sudo, no entitlements, no
# LaunchAgent, no TCC prompt.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT=/tmp/ioreport-poc
BIN="$OUT/ioreport-poc"
mkdir -p "$OUT"

# Build before dispatching: the experiment batch runs the binary directly.
xcrun swiftc -O "$HERE/ioreport-poc.swift" -o "$BIN" || exit 1

if [[ "${1:-}" == "experiments" ]]; then
    command -v /tmp/gpuload/gpuload >/dev/null 2>&1 || echo "note: GPU_LOAD tool missing, gpu-load probes will be skipped-ish" >&2
    exec bash "$HERE/run-experiments.sh" "$BIN"
fi

exec "$BIN" "$@"

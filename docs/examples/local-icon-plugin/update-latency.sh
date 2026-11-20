#!/bin/bash
# Writes a new latency reading atomically. Point DATA at an enabled package's
# data.json and run this from your own scheduler.
set -euo pipefail
data="${1:?usage: update-latency.sh /path/to/package/data.json 57}"
ms="${2:?usage: update-latency.sh /path/to/package/data.json 57}"
dir="$(dirname "$data")"
tmp="$(mktemp "$dir/.data.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<JSON
{"schemaVersion":1,"observedAt":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","values":{"value":"${ms} ms"}}
JSON
mv -f "$tmp" "$data"

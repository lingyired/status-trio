#!/usr/bin/env bash
# Fails when a generated MobileBattery table drifts from
# Support/mobile-battery-dependencies.json.
#
# Both docs/legal/third-party-licenses.md and the shipped helper NOTICE.md embed
# the same generated table between identical markers. Editing the JSON is the
# only supported way to change versions; regenerate the tables afterwards.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/Support/mobile-battery-dependencies.json"
RENDERER="$ROOT/scripts/render-mobile-battery-license-table.py"
BEGIN='<!-- BEGIN GENERATED: mobile-battery-dependencies -->'
END='<!-- END GENERATED: mobile-battery-dependencies -->'

DOCUMENTS=(
    "$ROOT/docs/legal/third-party-licenses.md"
    "$ROOT/Support/MobileBatteryHelper/ThirdPartyNotices/NOTICE.md"
)

generated="$(python3 "$RENDERER" "$MANIFEST")"
status=0

for doc in "${DOCUMENTS[@]}"; do
    if [[ ! -f "$doc" ]]; then
        echo "Error: missing document: $doc" >&2
        status=1
        continue
    fi

    actual="$(python3 - "$doc" "$BEGIN" "$END" <<'PY'
import sys

doc, begin, end = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(doc, encoding="utf-8").read()
if begin not in text or end not in text:
    sys.exit(f"generated markers not found in {doc}")
print(text.split(begin, 1)[1].split(end, 1)[0].strip())
PY
)"

    if [[ "$generated" != "$actual" ]]; then
        echo "Error: the MobileBattery table in ${doc#$ROOT/} is stale." >&2
        echo "Regenerate it with scripts/render-mobile-battery-license-table.py." >&2
        diff <(printf '%s\n' "$generated") <(printf '%s\n' "$actual") >&2 || true
        status=1
    fi
done

if [[ "$status" -eq 0 ]]; then
    echo "Generated MobileBattery tables match Support/mobile-battery-dependencies.json."
fi

exit "$status"

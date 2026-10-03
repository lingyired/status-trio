#!/usr/bin/env bash
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" ]]; then
    echo "Usage: $0 <StatusTrio.app>" >&2
    exit 2
fi
CONTENTS="$APP/Contents"
HELPER="$CONTENTS/Helpers/StatusTrioMobileBatteryHelper"
LIBRARY_DIR="$CONTENTS/Frameworks/MobileBattery"
EXPECTED_MINOS="15.0"

if [[ ! -x "$HELPER" || ! -d "$LIBRARY_DIR" ]]; then
    echo "Error: the packaged mobile battery helper or its library directory is missing." >&2
    exit 1
fi

HELPER_ARCHS="$(lipo -archs "$HELPER")"
if [[ "${UNIVERSAL_BUILD:-0}" == "1" ]]; then
    for arch in arm64 x86_64; do
        if [[ " $HELPER_ARCHS " != *" $arch "* ]]; then
            echo "Error: helper is missing required $arch architecture slice." >&2
            exit 1
        fi
    done
fi

BINARIES=("$HELPER")
while IFS= read -r -d '' library; do
    BINARIES+=("$library")
done < <(find "$LIBRARY_DIR" -maxdepth 1 -type f -name '*.dylib*' -print0 | sort -z)
if [[ "${#BINARIES[@]}" -lt 2 ]]; then
    echo "Error: no source-built runtime dylibs were packaged." >&2
    exit 1
fi

for arch in $HELPER_ARCHS; do
    if ! otool -arch "$arch" -l "$HELPER" | python3 "$(dirname -- "${BASH_SOURCE[0]}")/otool-rpaths.py" | grep -Fxq '@executable_path/../Frameworks/MobileBattery'; then
        echo "Error: helper $arch slice is missing its bundled-library run path." >&2
        exit 1
    fi
done

for binary in "${BINARIES[@]}"; do
    archs="$(lipo -archs "$binary")"
    if [[ "$archs" != "$HELPER_ARCHS" ]]; then
        echo "Error: architecture mismatch in $(basename "$binary"): $archs (helper: $HELPER_ARCHS)." >&2
        exit 1
    fi
    bash "$(dirname -- "${BASH_SOURCE[0]}")/verify-platform-version.sh" "$binary" "$EXPECTED_MINOS" 26
    codesign --verify --strict --verbose=2 "$binary"

    while IFS= read -r rpath; do
        if ! bash "$(dirname -- "${BASH_SOURCE[0]}")/check-mobile-battery-rpath.sh" "$rpath" "$LIBRARY_DIR"; then
            echo "Error: $(basename "$binary") has an unapproved LC_RPATH: $rpath" >&2
            exit 1
        fi
    done < <(otool -l "$binary" | python3 "$(dirname -- "${BASH_SOURCE[0]}")/otool-rpaths.py")

    while IFS= read -r dependency; do
        if ! bash "$(dirname -- "${BASH_SOURCE[0]}")/check-mobile-battery-dependency.sh" "$dependency" "$LIBRARY_DIR"; then
            echo "Error: $(basename "$binary") has an unapproved dependency: $dependency" >&2
            exit 1
        fi
    done < <(otool -L "$binary" | python3 "$(dirname -- "${BASH_SOURCE[0]}")/otool-dependencies.py")
done

codesign --verify --deep --strict --verbose=2 "$APP"
LIST_OUTPUT="$(env -i PATH="/usr/bin:/bin:/usr/sbin:/sbin" LC_ALL=C "$HELPER" --list)"
python3 - "$LIST_OUTPUT" <<'PY'
import json, sys
payload = json.loads(sys.argv[1])
assert payload.get("schemaVersion") == 1
assert isinstance(payload.get("phones"), list)
for phone in payload["phones"]:
    assert isinstance(phone.get("id"), str) and phone["id"]
    assert phone.get("transport") in ("usb", "network")
    assert phone.get("availableTransports") in (["usb"], ["network"], ["usb", "network"])
PY

echo "Mobile battery helper bundle verified: $HELPER_ARCHS"

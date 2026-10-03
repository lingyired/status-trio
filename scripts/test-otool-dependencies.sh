#!/usr/bin/env bash
set -euo pipefail

PARSER="$(dirname -- "${BASH_SOURCE[0]}")/otool-dependencies.py"
OUTPUT="$(cat <<'FIXTURE' | python3 "$PARSER"
StatusTrioMobileBatteryHelper (architecture x86_64):
	@rpath/libimobiledevice-1.0.6.dylib (compatibility version 7.0.0, current version 7.0.0)
	/opt/homebrew/opt/lib space/libplist/libplist-2.0.dylib (compatibility version 5.0.0, current version 5.0.0)
StatusTrioMobileBatteryHelper (architecture arm64):
	/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation (compatibility version 300.0.0, current version 300.0.0)
FIXTURE
)"
EXPECTED="$(cat <<'DEPENDENCIES'
@rpath/libimobiledevice-1.0.6.dylib
/opt/homebrew/opt/lib space/libplist/libplist-2.0.dylib
/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
DEPENDENCIES
)"
if [[ "$OUTPUT" != "$EXPECTED" ]]; then
    echo "otool dependency parser regression: unexpected extraction" >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
fi
if [[ "$OUTPUT" == *"StatusTrioMobileBatteryHelper (architecture"* ]]; then
    echo "otool dependency parser included an architecture header" >&2
    exit 1
fi
if [[ "$OUTPUT" != *"/opt/homebrew/opt/lib space/libplist/libplist-2.0.dylib"* ]]; then
    echo "otool dependency parser lost a path containing spaces" >&2
    exit 1
fi

CHECKER="$(dirname -- "${BASH_SOURCE[0]}")/check-mobile-battery-dependency.sh"
for forbidden in "/opt/homebrew/opt/lib space/libplist.dylib" "/usr/local/lib/libplist.dylib" "/tmp/project/.build/mobile-battery/arm64/lib/libplist.dylib"; do
    if bash "$CHECKER" "$forbidden" /tmp/no-libraries >/dev/null 2>&1; then
        echo "dependency checker accepted forbidden path: $forbidden" >&2
        exit 1
    fi
done
echo "otool dependency parser and rejection fixtures passed"

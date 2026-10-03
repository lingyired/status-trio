#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PARSER="$ROOT/scripts/otool-rpaths.py"
CHECKER="$ROOT/scripts/check-mobile-battery-rpath.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
LIBRARY_DIR="$TEST_ROOT/Contents/Frameworks/MobileBattery"
mkdir -p "$LIBRARY_DIR"
OUTPUT="$(cat <<'FIXTURE' | python3 "$PARSER"
StatusTrioHelper (architecture x86_64):
Load command 7
      cmd LC_RPATH
  cmdsize 48
     path /tmp/project/.build/mobile-battery/x86_64/prefix/lib (offset 12)
Load command 8
      cmd LC_RPATH
  cmdsize 64
     path @executable_path/../Frameworks/MobileBattery (offset 12)
StatusTrioHelper (architecture arm64):
Load command 7
      cmd LC_RPATH
  cmdsize 48
     path /tmp/project/.build/mobile-battery/arm64/prefix/lib (offset 12)
FIXTURE
)"
EXPECTED="$(cat <<'RUNPATHS'
/tmp/project/.build/mobile-battery/x86_64/prefix/lib
@executable_path/../Frameworks/MobileBattery
/tmp/project/.build/mobile-battery/arm64/prefix/lib
RUNPATHS
)"
if [[ "$OUTPUT" != "$EXPECTED" ]]; then
    echo "otool runpath parser regression: unexpected extraction" >&2
    printf '%s\n' "$OUTPUT" >&2
    exit 1
fi

for forbidden in "/tmp/project/.build/mobile-battery/arm64/prefix/lib" "/opt/homebrew/lib" "@loader_path/../../outside"; do
    if bash "$CHECKER" "$forbidden" "$LIBRARY_DIR" >/dev/null 2>&1; then
        echo "runpath checker accepted unbundled path: $forbidden" >&2
        exit 1
    fi
done
bash "$CHECKER" "@executable_path/../Frameworks/MobileBattery" "$LIBRARY_DIR"
bash "$CHECKER" "/System/Library/Frameworks" "$LIBRARY_DIR"
echo "otool runpath parser and rejection fixtures passed"

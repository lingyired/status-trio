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

# A helper package built in one worktree may be reused from .build in another.
# build-app.sh must relocate those absolute install names to the bundled @rpath
# rather than leaving a dependency on the worktree that originally built them.
MAIN_ROOT="$TEST_ROOT/main-worktree"
CURRENT_ROOT="$TEST_ROOT/current-worktree"
OLD_LIBRARY_DIR="$MAIN_ROOT/.build/mobile-battery/arm64/prefix/lib"
mkdir -p "$OLD_LIBRARY_DIR" "$CURRENT_ROOT"
cat > "$TEST_ROOT/library.c" <<'C'
int status_trio_fixture(void) { return 42; }
C
cat > "$TEST_ROOT/tool.c" <<'C'
int status_trio_fixture(void);
int main(void) { return status_trio_fixture() == 42 ? 0 : 1; }
C
xcrun --sdk macosx clang -dynamiclib \
    -mmacosx-version-min=13.0 \
    -install_name "$OLD_LIBRARY_DIR/libfixture.dylib" \
    "$TEST_ROOT/library.c" \
    -o "$TEST_ROOT/libfixture.dylib"
xcrun --sdk macosx clang \
    -mmacosx-version-min=13.0 \
    "$TEST_ROOT/tool.c" "$TEST_ROOT/libfixture.dylib" \
    -o "$TEST_ROOT/tool"

cp "$TEST_ROOT/libfixture.dylib" "$CURRENT_ROOT/libfixture.dylib"
cp "$TEST_ROOT/tool" "$CURRENT_ROOT/tool"

awk '
    /^rewrite_mobile_battery_binary\(\) \{/ { printing = 1 }
    printing { print }
    printing && /^\}$/ { exit }
' "$ROOT/scripts/build-app.sh" > "$TEST_ROOT/rewrite.sh"
ROOT="$CURRENT_ROOT"
source "$TEST_ROOT/rewrite.sh"
rewrite_mobile_battery_binary "$CURRENT_ROOT/libfixture.dylib"
rewrite_mobile_battery_binary "$CURRENT_ROOT/tool"

if otool -D "$CURRENT_ROOT/libfixture.dylib" | tail -n 1 | grep -Fq "$OLD_LIBRARY_DIR"; then
    echo "mobile battery cache relocation left an absolute dylib install name." >&2
    exit 1
fi
if otool -L "$CURRENT_ROOT/tool" | grep -Fq "$OLD_LIBRARY_DIR"; then
    echo "mobile battery cache relocation left an absolute executable dependency." >&2
    exit 1
fi
otool -L "$CURRENT_ROOT/tool" | grep -Fq '@rpath/libfixture.dylib' || {
    echo "mobile battery cache relocation did not install the bundled @rpath dependency." >&2
    exit 1
}

echo "otool dependency relocation, runpath parser and rejection fixtures passed"

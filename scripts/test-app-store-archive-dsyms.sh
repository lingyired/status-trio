#!/usr/bin/env bash
# Offline fixtures for verify-app-store-archive-dsyms.sh.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIER="$ROOT/scripts/verify-app-store-archive-dsyms.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioArchiveDSYMs.XXXXXX")"
SCENARIOS=0
PASSED=0
trap '/bin/rm -rf "$WORK"' EXIT

fail() {
    echo "App Store archive dSYM contract failed: $*" >&2
    exit 1
}

expect_pass() {
    local label="$1"
    shift
    SCENARIOS=$((SCENARIOS + 1))
    if ! "$@" >"$WORK/stdout" 2>"$WORK/stderr"; then
        cat "$WORK/stdout" >&2
        cat "$WORK/stderr" >&2
        fail "$label was rejected"
    fi
    PASSED=$((PASSED + 1))
    printf 'PASS %02d: %s\n' "$SCENARIOS" "$label"
}

expect_fail_contains() {
    local label="$1"
    local expected="$2"
    shift 2
    SCENARIOS=$((SCENARIOS + 1))
    if "$@" >"$WORK/stdout" 2>"$WORK/stderr"; then
        cat "$WORK/stdout" >&2
        fail "$label was accepted"
    fi
    if ! grep -Fq -- "$expected" "$WORK/stderr"; then
        cat "$WORK/stderr" >&2
        fail "$label failed without expected text '$expected'"
    fi
    PASSED=$((PASSED + 1))
    printf 'PASS %02d: %s\n' "$SCENARIOS" "$label"
}

[[ -x "$VERIFIER" ]] || fail "missing executable verifier at $VERIFIER"

make_fixture() {
    local name="$1"
    local archive="$WORK/$name.xcarchive"
    local app="$archive/Products/Applications/StatusTrio.app"
    local core="$app/Contents/Frameworks/StatusTrioCore.framework/Versions/A"
    local app_source="$WORK/$name-app.swift"
    local library_source="$WORK/$name-library.swift"
    mkdir -p \
        "$archive/dSYMs/StatusTrio.app.dSYM/Contents/Resources/DWARF" \
        "$archive/dSYMs/StatusTrioCore.framework.dSYM/Contents/Resources/DWARF" \
        "$app/Contents/MacOS" \
        "$core"
    cat >"$app_source" <<'SWIFT'
import Foundation
print("probe")
SWIFT
    cat >"$library_source" <<'SWIFT'
import Foundation
public func probe() {}
SWIFT
    xcrun --sdk macosx swiftc -target arm64-apple-macos13.0 \
        -g -o "$WORK/$name-app-arm64" "$app_source"
    xcrun --sdk macosx swiftc -target x86_64-apple-macos13.0 \
        -g -o "$WORK/$name-app-x86_64" "$app_source"
    cp "$WORK/$name-app-arm64" \
        "$archive/dSYMs/StatusTrio.app.dSYM/Contents/Resources/DWARF/StatusTrio"
    cp "$WORK/$name-app-x86_64" "$WORK/app-x86_64"
    lipo -create "$WORK/$name-app-arm64" "$WORK/app-x86_64" \
        -output "$app/Contents/MacOS/StatusTrio"

    xcrun --sdk macosx swiftc -target arm64-apple-macos13.0 \
        -g -emit-library -o "$WORK/$name-core-arm64" "$library_source"
    xcrun --sdk macosx swiftc -target x86_64-apple-macos13.0 \
        -g -emit-library -o "$WORK/$name-core-x86_64" "$library_source"
    cp "$WORK/$name-core-arm64" "$core/StatusTrioCore"
    cp "$WORK/$name-core-arm64" \
        "$archive/dSYMs/StatusTrioCore.framework.dSYM/Contents/Resources/DWARF/StatusTrioCore"
    # A second architecture keeps each fixture honest about Universal dSYMs.
    lipo -create \
        "$WORK/$name-app-arm64" "$WORK/app-x86_64" \
        -output "$archive/dSYMs/StatusTrio.app.dSYM/Contents/Resources/DWARF/StatusTrio"
    lipo -create \
        "$WORK/$name-core-arm64" "$WORK/$name-core-x86_64" \
        -output "$archive/dSYMs/StatusTrioCore.framework.dSYM/Contents/Resources/DWARF/StatusTrioCore"
    lipo -create \
        "$WORK/$name-core-arm64" "$WORK/$name-core-x86_64" \
        -output "$core/StatusTrioCore"
    rm -f "$WORK/app-x86_64"
    printf '%s\n' "$archive"
}

verify() {
    bash "$VERIFIER" "$1"
}

ARCHIVE="$(make_fixture valid)"
expect_pass "matching Universal app and framework dSYMs" verify "$ARCHIVE"

ARCHIVE="$(make_fixture missing-dsym)"
rm -rf "$ARCHIVE/dSYMs/StatusTrio.app.dSYM"
expect_fail_contains "missing app dSYM" "missing StatusTrio dSYM" verify "$ARCHIVE"

ARCHIVE="$(make_fixture empty-dsym)"
: >"$ARCHIVE/dSYMs/StatusTrioCore.framework.dSYM/Contents/Resources/DWARF/StatusTrioCore"
expect_fail_contains "empty framework dSYM" "StatusTrioCore DWARF is empty" verify "$ARCHIVE"

ARCHIVE="$(make_fixture single-arch-dsym)"
rm -f "$WORK/single.dSYM"
cp "$ARCHIVE/dSYMs/StatusTrio.app.dSYM/Contents/Resources/DWARF/StatusTrio" \
    "$WORK/single-app"
lipo -thin arm64 "$WORK/single-app" -output \
    "$ARCHIVE/dSYMs/StatusTrio.app.dSYM/Contents/Resources/DWARF/StatusTrio"
expect_fail_contains "single-architecture app dSYM" \
    "StatusTrio dSYM is not Universal" verify "$ARCHIVE"

ARCHIVE="$(make_fixture wrong-uuid)"
cp "$WORK/wrong-uuid-core-arm64" "$WORK/wrong-uuid-app-arm64"
cp "$WORK/wrong-uuid-core-x86_64" "$WORK/wrong-uuid-app-x86_64"
lipo -create "$WORK/wrong-uuid-app-arm64" "$WORK/wrong-uuid-app-x86_64" \
    -output "$ARCHIVE/dSYMs/StatusTrio.app.dSYM/Contents/Resources/DWARF/StatusTrio"
expect_fail_contains "mismatched app dSYM UUIDs" \
    "StatusTrio dSYM UUIDs do not match" verify "$ARCHIVE"

echo "App Store archive dSYM contract passed: $SCENARIOS/$SCENARIOS scenarios"

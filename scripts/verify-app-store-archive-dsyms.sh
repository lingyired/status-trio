#!/usr/bin/env bash
# Fail closed unless the Store archive carries matching Universal dSYMs.
set -euo pipefail

ARCHIVE="${1:-}"
if [[ -z "$ARCHIVE" ]]; then
    echo "Usage: $0 ARCHIVE_PATH" >&2
    exit 2
fi

fail() {
    echo "Error: $*" >&2
    exit 1
}

[[ -d "$ARCHIVE" ]] || fail "missing archive directory: $ARCHIVE"
APP="$ARCHIVE/Products/Applications/StatusTrio.app"
DSYM_ROOT="$ARCHIVE/dSYMs"

uuid_map() {
    local path="$1"
    local output
    output="$(dwarfdump --uuid "$path" 2>&1)" ||
        fail "dwarfdump cannot read $path: $output"
    printf '%s\n' "$output" |
        sed -nE 's/^UUID: ([0-9A-F-]+) \(([^)]+)\).*$/\2 \1/p' |
        LC_ALL=C sort -u
}

verify_component() {
    local label="$1"
    local binary="$2"
    local dsym="$3"
    local dwarf="$dsym/Contents/Resources/DWARF/$label"
    local binary_archs dsym_archs binary_uuids dsym_uuids

    [[ -f "$binary" ]] || fail "missing $label binary at $binary"
    [[ -d "$dsym" ]] || fail "missing $label dSYM at $dsym"
    [[ -f "$dwarf" ]] || fail "missing $label DWARF at $dwarf"
    [[ -s "$dwarf" ]] || fail "$label DWARF is empty: $dwarf"

    binary_archs="$(lipo -archs "$binary" 2>/dev/null)" ||
        fail "cannot read $label binary architectures"
    dsym_archs="$(lipo -archs "$dwarf" 2>/dev/null)" ||
        fail "cannot read $label dSYM architectures"
    [[ "$binary_archs" == "arm64 x86_64" || "$binary_archs" == "x86_64 arm64" ]] ||
        fail "$label binary is not Universal arm64+x86_64: $binary_archs"
    [[ "$dsym_archs" == "arm64 x86_64" || "$dsym_archs" == "x86_64 arm64" ]] ||
        fail "$label dSYM is not Universal arm64+x86_64: $dsym_archs"

    binary_uuids="$(uuid_map "$binary")"
    dsym_uuids="$(uuid_map "$dwarf")"
    [[ -n "$binary_uuids" ]] || fail "$label binary has no readable UUIDs"
    [[ "$binary_uuids" == "$dsym_uuids" ]] ||
        fail "$label dSYM UUIDs do not match its binary"
    printf '%s dSYM verified: %s\n' "$label" "$dsym"
}

verify_component \
    "StatusTrio" \
    "$APP/Contents/MacOS/StatusTrio" \
    "$DSYM_ROOT/StatusTrio.app.dSYM"
verify_component \
    "StatusTrioCore" \
    "$APP/Contents/Frameworks/StatusTrioCore.framework/Versions/A/StatusTrioCore" \
    "$DSYM_ROOT/StatusTrioCore.framework.dSYM"

echo "App Store archive dSYM contract passed: $ARCHIVE"

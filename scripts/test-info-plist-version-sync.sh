#!/usr/bin/env bash
# Offline fixtures for scripts/check-info-plist-version-sync.sh.
#
# The check has two jobs: ordinary local verification must accept a pending
# version that leads the published appcast, and the publish gate must require an
# exact match. A regression (or the same build with a different marketing
# version) fails in both modes. No network, no real appcast, no real release.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioVersionSync.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "info-plist version sync contract failed: $*" >&2; exit 1; }

make_fixture() {
    local fixture="$1" plist_version="$2" plist_build="$3" feed_version="$4" feed_build="$5"
    mkdir -p "$fixture/Support"
    cat > "$fixture/Support/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>${plist_version}</string>
    <key>CFBundleVersion</key>
    <string>${plist_build}</string>
</dict>
</plist>
PLIST
    cat > "$fixture/appcast.xml" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
    <title>Status Trio</title>
    <item>
        <title>Older</title>
        <sparkle:version>${feed_build}</sparkle:version>
        <sparkle:shortVersionString>${feed_version}</sparkle:shortVersionString>
    </item>
</channel>
</rss>
APPCAST
}

# Writes a two-item feed whose newer item is the given build/version, so the
# check must pick the highest build rather than the first item.
make_multi_item_fixture() {
    local fixture="$1" plist_version="$2" plist_build="$3" feed_version="$4" feed_build="$5"
    make_fixture "$fixture" "$plist_version" "$plist_build" "$feed_version" "$feed_build"
    python3 - "$fixture/appcast.xml" "$feed_version" "$feed_build" <<'PY'
import sys
path, version, build = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as fh:
    text = fh.read()
item = (
    "    <item>\n"
    "        <title>Newest</title>\n"
    f"        <sparkle:version>{build}</sparkle:version>\n"
    f"        <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
    "    </item>\n"
)
text = text.replace("</channel>", item + "</channel>")
with open(path, "w") as fh:
    fh.write(text)
PY
}

run_check() {
    local fixture="$1"; shift
    STATUS_TRIO_ROOT="$fixture" bash "$ROOT/scripts/check-info-plist-version-sync.sh" "$@" \
        >"$WORK/out" 2>&1
}

expect_pass() {
    local name="$1" fixture="$2"; shift 2
    if ! run_check "$fixture" "$@"; then
        cat "$WORK/out" >&2
        fail "$name: expected pass, got failure"
    fi
}

expect_fail() {
    local name="$1" fixture="$2"; shift 2
    if run_check "$fixture" "$@"; then
        fail "$name: expected failure, got pass"
    fi
}

published="$WORK/published"
make_multi_item_fixture "$published" "1.10.5" "105" "1.10.5" "105"

# Equal metadata passes both modes.
expect_pass "equal / local" "$published"
expect_pass "equal / exact" "$published" --exact

# A pending release ahead of the feed is normal local work; publish still needs
# the feed to catch up.
ahead="$WORK/ahead"
make_fixture "$ahead" "1.10.6" "106" "1.10.5" "105"
expect_pass "pending ahead / local" "$ahead"
expect_fail "pending ahead / exact" "$ahead" --exact

# A patch ahead and numeric ordering (1.10.10 > 1.10.9) both count as ahead.
numeric_ahead="$WORK/numeric-ahead"
make_fixture "$numeric_ahead" "1.10.10" "110" "1.10.9" "109"
expect_pass "numeric pending ahead / local" "$numeric_ahead"

# A regression fails locally as well as for publishing.
behind="$WORK/behind"
make_fixture "$behind" "1.10.4" "104" "1.10.5" "105"
expect_fail "stale build / local" "$behind"
expect_fail "stale build / exact" "$behind" --exact

behind_version="$WORK/behind-version"
make_fixture "$behind_version" "1.9.5" "106" "1.10.5" "105"
expect_fail "stale marketing version / local" "$behind_version"

# Same build, different marketing version: the two metadata sources disagree.
drift="$WORK/drift"
make_fixture "$drift" "1.10.6" "105" "1.10.5" "105"
expect_fail "same build different version / local" "$drift"
expect_fail "same build different version / exact" "$drift" --exact

# Malformed inputs fail closed.
missing_plist="$WORK/missing-plist"
mkdir -p "$missing_plist"
cat > "$missing_plist/appcast.xml" <<'APPCAST'
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel></channel></rss>
APPCAST
expect_fail "missing Info.plist" "$missing_plist"

empty_feed="$WORK/empty-feed"
mkdir -p "$empty_feed/Support"
cat > "$empty_feed/Support/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
cat > "$empty_feed/appcast.xml" <<'APPCAST'
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel></channel></rss>
APPCAST
expect_fail "feed without numeric item" "$empty_feed"

bad_build="$WORK/bad-build"
make_fixture "$bad_build" "1.10.5" "abc" "1.10.5" "105"
expect_fail "non-numeric CFBundleVersion" "$bad_build"

# Unknown arguments are a hard error rather than silently choosing a mode.
if run_check "$published" --keep-it-loose; then
    fail "unknown argument was accepted"
fi

echo "test-info-plist-version-sync: PASS"

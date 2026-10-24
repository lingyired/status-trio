#!/usr/bin/env bash
# Offline tests for App Store project generation and source membership.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR="$ROOT/scripts/generate-app-store-project.py"
XCODEGEN="${XCODEGEN:-/opt/homebrew/bin/xcodegen}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioAppStoreProject.XXXXXX")"
CASES=0
PASSES=0
trap '/bin/rm -rf "$WORK"' EXIT

fail() {
    echo "App Store project contract failed: $*" >&2
    exit 1
}

expect_pass() {
    local label="$1"
    shift
    CASES=$((CASES + 1))
    if ! "$@" >"$WORK/stdout" 2>"$WORK/stderr"; then
        cat "$WORK/stdout" >&2
        cat "$WORK/stderr" >&2
        fail "$label was rejected"
    fi
    PASSES=$((PASSES + 1))
    printf 'PASS %02d: %s\n' "$CASES" "$label"
}

expect_fail() {
    local label="$1"
    shift
    CASES=$((CASES + 1))
    if "$@" >"$WORK/stdout" 2>"$WORK/stderr"; then
        cat "$WORK/stdout" >&2
        fail "$label was accepted"
    fi
    PASSES=$((PASSES + 1))
    printf 'PASS %02d: %s\n' "$CASES" "$label"
}

expect_fail_contains() {
    local label="$1"
    local expected="$2"
    shift 2
    CASES=$((CASES + 1))
    local output
    output="$(mktemp "$WORK/expect-fail.XXXXXX")"
    if "$@" >"$WORK/stdout" 2>"$output"; then
        cat "$WORK/stdout" >&2
        fail "$label was accepted"
    fi
    if ! grep -Fq -- "$expected" "$output"; then
        cat "$output" >&2
        fail "$label failed without expected text '$expected'"
    fi
    PASSES=$((PASSES + 1))
    printf 'PASS %02d: %s\n' "$CASES" "$label"
}

make_fixture() {
    local fixture="$1"
    mkdir -p \
        "$fixture/scripts" \
        "$fixture/Support" \
        "$fixture/Sources/StatusTrio" \
        "$fixture/Sources/StatusTrioCore/App" \
        "$fixture/Sources/StatusTrioCore/Resources" \
        "$fixture/AppStore/Platform" \
        "$fixture/Distribution"
    cp "$GENERATOR" "$fixture/scripts/"
    cat > "$fixture/Support/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>1.7.0</string>
    <key>CFBundleVersion</key>
    <string>38</string>
</dict>
</plist>
PLIST
    printf 'import AppKit\n' > "$fixture/Sources/StatusTrio/main.swift"
    printf '@preconcurrency import CoreBluetooth\nimport AppKit\nimport notify\nfinal class SharedProbe {}\n' \
        > "$fixture/Sources/StatusTrioCore/App/SharedProbe.swift"
    printf 'import AppKit\nimport Sparkle\nfinal class DirectProbe {}\n' \
        > "$fixture/Sources/StatusTrioCore/App/DirectProbe.swift"
    for locale in \
        ar de en es fr it ja ko pt-BR ru zh-Hans zh-Hant; do
        mkdir -p "$fixture/Sources/StatusTrioCore/Resources/${locale}.lproj"
        cat > "$fixture/Sources/StatusTrioCore/Resources/${locale}.lproj/InfoPlist.strings" <<'STRINGS'
"NSLocationUsageDescription" = "Fixture location purpose.";
"NSLocationWhenInUseUsageDescription" = "Fixture location purpose.";
"NSBluetoothAlwaysUsageDescription" = "Fixture Bluetooth purpose.";
STRINGS
    done
    printf '"probe" = "probe";\n' \
        > "$fixture/Sources/StatusTrioCore/Resources/en.lproj/Localizable.strings"
    sips -s format png -z 16 16 "$ROOT/Support/AppIcon.png" \
        --out "$fixture/Support/AppIcon.png" >/dev/null
    cp "$ROOT/Distribution/AppStore.entitlements" \
        "$fixture/Distribution/AppStore.entitlements"
    printf 'Sources/StatusTrioCore/App/DirectProbe.swift\n' \
        > "$fixture/AppStore/direct-only-sources.txt"
    cat > "$fixture/AppStore/Platform/StoreResourceBundle.swift" <<'SWIFT'
import Foundation
extension Bundle { static var module: Bundle { .main } }
SWIFT
    printf 'import Foundation\nfinal class StorePlatformProbe {}\n' \
        > "$fixture/AppStore/Platform/StorePlatformProbe.swift"
    cat > "$fixture/AppStore/PrivacyInfo.xcprivacy" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
</dict>
</plist>
PLIST
}

run_generator() {
    local fixture="$1"
    shift
    python3 "$fixture/scripts/generate-app-store-project.py" \
        --repo-root "$fixture" \
        --project "$fixture/AppStore/project.json" \
        --output-root "$fixture/.build/app-store" \
        "$@"
}

run_membership_check() {
    local fixture="$1"
    python3 "$fixture/scripts/generate-app-store-project.py" \
        --repo-root "$fixture" \
        --check-membership-only
}

run_xcodegen_parse() {
    local fixture="$1"
    local project_dir="$fixture/.build/app-store/XcodeProject"
    mkdir -p "$project_dir"
    "$XCODEGEN" generate \
        --spec "$fixture/AppStore/project.json" \
        --project "$project_dir" \
        --project-root "$fixture" \
        --quiet
    python3 "$GENERATOR" \
        --repo-root "$fixture" \
        --validate-xcode-project "$project_dir/StatusTrioAppStore.xcodeproj"
    xcodebuild -project "$project_dir/StatusTrioAppStore.xcodeproj" -list >/dev/null
}

make_duplicate_group_project() {
    local fixture="$1"
    local project_dir="$fixture/.build/duplicate-group"
    python3 - "$fixture/AppStore/project.json" \
        "$fixture/AppStore/project.duplicate.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    spec = json.load(handle)
spec["options"]["createIntermediateGroups"] = True
core = spec["targets"]["StatusTrioCore"]
core["sources"] = [
    entry
    for entry in core["sources"]
    if entry.get("buildPhase") != "resources"
] + [
    {
        "path": "Sources/StatusTrioCore/Resources",
        "group": "Resources",
        "buildPhase": "resources",
    }
]
for entry in spec["targets"]["StatusTrio"]["sources"]:
    if (
        entry.get("buildPhase") == "resources"
        and entry["path"].endswith("/InfoPlist.strings")
    ):
        entry["group"] = "AppLocalization"
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(spec, handle, indent=2)
    handle.write("\n")
PY
    mkdir -p "$project_dir"
    "$XCODEGEN" generate \
        --spec "$fixture/AppStore/project.duplicate.json" \
        --project "$project_dir" \
        --project-root "$fixture" \
        --quiet >"$WORK/duplicate-xcodegen.stdout" \
        2>"$WORK/duplicate-xcodegen.stderr"
}

validate_duplicate_group_project() {
    local fixture="$1"
    python3 "$GENERATOR" \
        --repo-root "$fixture" \
        --validate-xcode-project \
        "$fixture/.build/duplicate-group/StatusTrioAppStore.xcodeproj"
}

assert_membership() {
    local fixture="$1"
    python3 - "$fixture/.build/app-store/source-membership.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    audit = json.load(handle)
assert audit["included_sources"] == [
    "AppStore/Platform/StorePlatformProbe.swift",
    "AppStore/Platform/StoreResourceBundle.swift",
    "Sources/StatusTrioCore/App/SharedProbe.swift",
], audit["included_sources"]
assert audit["excluded_sources"] == ["Sources/StatusTrioCore/App/DirectProbe.swift"], audit["excluded_sources"]
assert "AppStore/Platform/StorePlatformProbe.swift" in audit["included_sources"]
assert "AppStore/Platform/StoreResourceBundle.swift" in audit["included_sources"]
assert set(audit) == {
    "schema_version",
    "channel",
    "repository_root",
    "included_sources",
    "excluded_sources",
    "source_sha",
    "linked_frameworks",
    "swift_defines",
    "compiled_sources",
    "derived_sources",
    "swift_file_lists",
    "source_tree_sha256",
}
PY
}

assert_generated_files() {
    local fixture="$1"
    local version="${2:-1.7.0}"
    local build="${3:-38}"
    grep -Fq "ST_MARKETING_VERSION = $version" "$fixture/AppStore/Version.xcconfig" ||
        fail "generated version xcconfig is wrong"
    grep -Fq "ST_BUILD_NUMBER = $build" "$fixture/AppStore/Version.xcconfig" ||
        fail "generated build xcconfig is wrong"
    grep -Fq "MARKETING_VERSION = $version" "$fixture/AppStore/Version.xcconfig" ||
        fail "generated marketing version is wrong"
    grep -Fq "CURRENT_PROJECT_VERSION = $build" "$fixture/AppStore/Version.xcconfig" ||
        fail "generated current project version is wrong"
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "$fixture/AppStore/Info.plist" | grep -Fxq "$version" ||
        fail "generated Store Info.plist version is wrong"
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
        "$fixture/AppStore/Info.plist" | grep -Fxq "$build" ||
        fail "generated Store Info.plist build is wrong"
    for entitlement in \
        com.apple.security.app-sandbox \
        com.apple.security.network.client \
        com.apple.security.device.bluetooth \
        com.apple.security.personal-information.location; do
        /usr/libexec/PlistBuddy -c "Print :$entitlement" \
            "$fixture/Distribution/AppStore.entitlements" | grep -Fxq true ||
            fail "generated Store entitlements omit $entitlement"
    done
    if /usr/libexec/PlistBuddy -c "Print :com.apple.security.device.usb" \
        "$fixture/Distribution/AppStore.entitlements" >/dev/null 2>&1; then
        fail "generated Store entitlements include USB"
    fi
    if /usr/libexec/PlistBuddy -c "Print :com.apple.security.network.server" \
        "$fixture/Distribution/AppStore.entitlements" >/dev/null 2>&1; then
        fail "generated Store entitlements include network.server"
    fi
    if /usr/libexec/PlistBuddy -c "Print :SUFeedURL" \
        "$fixture/AppStore/Info.plist" >/dev/null 2>&1; then
        fail "generated Store Info.plist contains SUFeedURL"
    fi
}

assert_app_category() {
    local fixture="$1"
    local category
    category="$(
        /usr/libexec/PlistBuddy -c "Print :LSApplicationCategoryType" \
            "$fixture/AppStore/Info.plist"
    )"
    [[ "$category" == "public.app-category.utilities" ]] ||
        fail "generated Store Info.plist category is $category"
}

assert_project_safety() {
    local fixture="$1"
    python3 - "$fixture/AppStore/project.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    spec = json.load(handle)
targets = spec["targets"]
assert "StatusTrioCore" in targets
assert "StatusTrio" in targets
sources = [entry["path"] for entry in targets["StatusTrioCore"]["sources"]]
assert "Sources/StatusTrioCore/App/SharedProbe.swift" in sources
assert "Sources/StatusTrioCore/App/DirectProbe.swift" not in sources
assert "AppStore/Platform/StoreResourceBundle.swift" in sources
assert targets["StatusTrioCore"]["settings"]["base"]["PRODUCT_MODULE_NAME"] == "StatusTrioCore"
assert targets["StatusTrioCore"]["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"] == "com.lingsmbp.StatusTrio.AppStore.Core"
assert targets["StatusTrioCore"]["settings"]["base"]["SKIP_INSTALL"] is True
assert targets["StatusTrioCore"]["settings"]["base"]["LD_DYLIB_INSTALL_NAME"] == (
    "@rpath/StatusTrioCore.framework/Versions/A/StatusTrioCore"
)
assert targets["StatusTrioCore"]["settings"]["base"]["DYLIB_INSTALL_NAME_BASE"] == "@rpath"
assert targets["StatusTrio"]["settings"]["base"]["PRODUCT_BUNDLE_IDENTIFIER"] == (
    "com.lingsmbp.StatusTrio.AppStore"
)
assert targets["StatusTrio"]["settings"]["base"]["INFOPLIST_FILE"] == (
    "../../../AppStore/Info.plist"
)
assert targets["StatusTrio"]["settings"]["base"]["CODE_SIGN_ENTITLEMENTS"] == (
    "../../../Distribution/AppStore.entitlements"
)
assert targets["StatusTrio"]["settings"]["base"]["SKIP_INSTALL"] is False
assert targets["StatusTrio"]["productName"] == "StatusTrio"
assert targets["StatusTrio"]["settings"]["base"]["PRODUCT_NAME"] == "StatusTrio"
assert spec["configs"]["Release"]["DEBUG_INFORMATION_FORMAT"] == "dwarf-with-dsym"
assert spec["configs"]["Release"]["COPY_PHASE_STRIP"] is False
app_sources = targets["StatusTrio"]["sources"]
localizations = [
    entry["path"]
    for entry in app_sources
    if entry.get("buildPhase") == "resources"
    and entry["path"].endswith("/InfoPlist.strings")
]
assert len(localizations) == 12, localizations
assert all(path.endswith("/InfoPlist.strings") for path in localizations)
assert "Sources/StatusTrioCore/Resources/en.lproj/InfoPlist.strings" in localizations
assert "Sources/StatusTrioCore/Resources/zh-Hans.lproj/InfoPlist.strings" in localizations
app_resources = [
    entry for entry in app_sources if entry.get("buildPhase") == "resources"
]
assert len(app_resources) == 14, app_resources
assert any(
    entry["path"].endswith("/StatusTrioAppStore.icns")
    for entry in app_resources
), app_resources
assert any(
    entry["path"] == "AppStore/PrivacyInfo.xcprivacy"
    for entry in app_resources
), app_resources
assert "resources" not in targets["StatusTrio"], targets["StatusTrio"]
core_sources = targets["StatusTrioCore"]["sources"]
core_resources = [
    entry for entry in core_sources if entry.get("buildPhase") == "resources"
]
assert len(core_resources) == 13, core_resources
assert all(entry["group"] == "SharedStoreResources" for entry in core_resources)
assert "Sources/StatusTrioCore/Resources" not in {
    entry["path"] for entry in core_resources
}
assert {
    entry["path"] for entry in core_resources
} == {
    "Sources/StatusTrioCore/Resources/en.lproj/Localizable.strings",
    *{
        f"Sources/StatusTrioCore/Resources/{locale}.lproj/InfoPlist.strings"
        for locale in (
            "ar", "de", "en", "es", "fr", "it", "ja", "ko",
            "pt-BR", "ru", "zh-Hans", "zh-Hant",
        )
    },
}, core_resources
assert all(
    entry["group"] == "SharedStoreResources"
    for entry in app_resources
    if entry["path"].endswith("/InfoPlist.strings")
)
assert "resources" not in targets["StatusTrioCore"], targets["StatusTrioCore"]
serialized = json.dumps(spec)
for forbidden in ("Sparkle", "DDCPrivateAPI", "PowerHelperProtocol", "CoreDisplay"):
    assert forbidden not in serialized, forbidden
PY
}

[[ -f "$GENERATOR" ]] || fail "missing generator at $GENERATOR"
[[ -x "$XCODEGEN" ]] || fail "missing xcodegen at $XCODEGEN"

# 0. Build CLI contract: no real build is needed to check argument handling,
# signing mode selection, isolated paths, and archive hand-off.
grep -Fq 'STORE_APP="$ROOT/dist/AppStore/StatusTrio.app"' \
    "$ROOT/scripts/build-app-store.sh" ||
    fail "Store app output path is not isolated"
grep -Fq 'APP_STORE_ARCHIVE_PATH' "$ROOT/scripts/build-app-store.sh" ||
    fail "Store archive environment hand-off is missing"
expect_pass "build CLI declares unsigned mode" grep -Fq \
    'APP_STORE_UNSIGNED' "$ROOT/scripts/build-app-store.sh"
expect_pass "build CLI records real SwiftFileList evidence" grep -Fq \
    -- '--record-compiled-sources' "$ROOT/scripts/build-app-store.sh"
expect_pass "build CLI verifies source closure" grep -Fq \
    -- '--verify-closure-audit' "$ROOT/scripts/build-app-store.sh"
expect_pass "build CLI records the actual action and configuration" python3 - \
    "$ROOT/scripts/build-app-store.sh" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
assert '--record-configuration "$CONFIGURATION"' in text
assert '--record-build-action "$BUILD_ACTION"' in text
assert 'BUILD_ACTION="archive"' in text
assert 'BUILD_ACTION="build"' in text
PY
expect_pass "build CLI freezes the pre-build source digest" python3 - \
    "$ROOT/scripts/build-app-store.sh" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
capture = text.index('SOURCE_TREE_SHA256="$(')
build = text.index('xcodebuild "${xcode_args[@]}"')
record = text.index('--expected-source-tree-sha256 "$SOURCE_TREE_SHA256"')
assert capture < build < record
PY
expect_pass "build CLI signs embedded frameworks first" grep -Fq \
    -- "-depth -type d -name '*.framework'" "$ROOT/scripts/build-app-store.sh"
expect_pass "build CLI pins exact XcodeGen" grep -Fq \
    -- '2.46.0' "$ROOT/scripts/build-app-store.sh"
expect_pass "build CLI never overrides target bundle IDs" python3 - \
    "$ROOT/scripts/build-app-store.sh" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
assert not re.search(r"PRODUCT_BUNDLE_IDENTIFIER\s*=", text), text
assert 'xcode_args+=(' in text
PY
expect_pass "build CLI requires and always runs the bundle verifier" python3 - \
    "$ROOT/scripts/build-app-store.sh" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
assert '[[ -f "$VERIFIER" && -r "$VERIFIER" ]]' in text
assert re.search(
    r'^\s*bash "\$VERIFIER" "\$STORE_APP" --unsigned$',
    text,
    re.MULTILINE,
)
assert re.search(r'^\s*bash "\$VERIFIER" "\$STORE_APP"$', text, re.MULTILINE)
assert '[[ -x "$VERIFIER" ]]' not in text
PY
expect_pass "build CLI generates icon and verifies both binaries" python3 - \
    "$ROOT/scripts/build-app-store.sh" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
copy_index = text.index('ditto "$BUILT_APP" "$STORE_APP"')
icon_index = text.index('APP_ICON_ICNS="$STORE_APP/Contents/Resources/StatusTrioAppStore.icns"')
framework_sign_index = text.index('codesign --force --sign "$SIGNING_IDENTITY" "$framework"')
app_sign_index = text.index('--entitlements "$ENTITLEMENTS" "$STORE_APP"')
assert copy_index < icon_index < framework_sign_index < app_sign_index
assert text.count('verify-platform-version.sh') == 2
assert 'StatusTrioCore.framework/StatusTrioCore' in text
PY
expect_pass "build CLI runs the archive dSYM gate before copying" python3 - \
    "$ROOT/scripts/build-app-store.sh" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
archive = text.index('xcodebuild "${xcode_args[@]}"')
dsym = text.index('bash "$DSYM_VERIFIER" "$ARCHIVE_PATH"')
copy = text.index('ditto "$BUILT_APP" "$STORE_APP"')
assert archive < dsym < copy
PY
expect_pass "build CLI requires the privacy manifest before and after copy" python3 - \
    "$ROOT/scripts/build-app-store.sh" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
source_check = text.index('--check-privacy-manifest "$PRIVACY_MANIFEST"')
build_index = text.index('xcodebuild "${xcode_args[@]}"')
copy_index = text.index('ditto "$BUILT_APP" "$STORE_APP"')
bundle_check = text.index(
    '--check-privacy-manifest "$PRIVACY_MANIFEST_IN_BUNDLE"'
)
sign_index = text.index('codesign --force --sign "$SIGNING_IDENTITY" \\')
assert source_check < build_index < copy_index < bundle_check < sign_index
PY
expect_pass "build CLI validates PBX resource paths before xcodebuild" python3 - \
    "$ROOT/scripts/build-app-store.sh" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
validate_index = text.index('--validate-xcode-project "$XCODE_PROJECT"')
build_index = text.index('xcodebuild "${xcode_args[@]}"')
assert validate_index < build_index
PY
expect_pass "archive path guard uses canonical containment" python3 - \
    "$ROOT/scripts/build-app-store.sh" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
assert "Path(sys.argv[1]).resolve(strict=True)" in text
assert "Path(sys.argv[2])" in text
assert "candidate.resolve(strict=False)" in text
assert "resolved.relative_to(root)" in text
assert 'if resolved == root:' in text
assert "root / \"dist\"" in text
PY

ARCHIVE_SYMLINK_ROOT="$(mktemp -d "$ROOT/AppStore/.archive-path.XXXXXX")"
trap '/bin/rm -rf "$ARCHIVE_SYMLINK_ROOT" "$WORK"' EXIT
ln -s "$WORK/outside-archive" "$ARCHIVE_SYMLINK_ROOT/escape.xcarchive"
expect_fail_contains "archive path parent traversal" "APP_STORE_ARCHIVE_PATH" \
    env APP_STORE_ARCHIVE_PATH="../outside.xcarchive" \
    bash "$ROOT/scripts/build-app-store.sh" release no-open
expect_fail_contains "archive path repository root" "APP_STORE_ARCHIVE_PATH" \
    env APP_STORE_ARCHIVE_PATH="$ROOT" \
    bash "$ROOT/scripts/build-app-store.sh" release no-open
expect_fail_contains "archive path protected dist output" "APP_STORE_ARCHIVE_PATH" \
    env APP_STORE_ARCHIVE_PATH="$ROOT/dist/AppStore/escape.xcarchive" \
    bash "$ROOT/scripts/build-app-store.sh" release no-open
expect_fail_contains "archive path symlink escape" "APP_STORE_ARCHIVE_PATH" \
    env APP_STORE_ARCHIVE_PATH="$ARCHIVE_SYMLINK_ROOT/escape.xcarchive" \
    bash "$ROOT/scripts/build-app-store.sh" release no-open

# 1. Positive generator and audit.
make_fixture "$WORK/positive"
export STATUS_TRIO_SOURCE_SHA=0123456789abcdef0123456789abcdef01234567
expect_pass "valid fixture generates project" run_generator "$WORK/positive"
expect_pass "valid fixture membership audit" assert_membership "$WORK/positive"
expect_pass "valid fixture generated version and entitlements" \
    assert_generated_files "$WORK/positive"
expect_pass "Store Info.plist declares the Utilities app category" \
    assert_app_category "$WORK/positive"
expect_pass "valid fixture source target safety" \
    assert_project_safety "$WORK/positive"
expect_pass "xcodegen parses and resolves nested real project paths" \
    run_xcodegen_parse "$WORK/positive"
expect_pass "generated project embeds and signs StoreCore" python3 - \
    "$WORK/positive/.build/app-store/XcodeProject/StatusTrioAppStore.xcodeproj/project.pbxproj" <<'PY'
import sys

text = open(sys.argv[1], encoding="utf-8").read()
assert "Embed Frameworks" in text
assert "CodeSignOnCopy" in text
assert "StatusTrioCore.framework in Embed Frameworks" in text
embed_index = text.index("StatusTrioCore.framework in Embed Frameworks")
settings_index = text.index("settings = {", embed_index)
attributes = text[settings_index:text.index("};", settings_index)]
assert "CodeSignOnCopy" in attributes, attributes
assert "RemoveHeadersOnCopy" in attributes, attributes
assert 'SKIP_INSTALL = YES;' in text
assert 'SKIP_INSTALL = NO;' in text
PY
expect_pass "generator schema has no compiled evidence" \
    python3 - "$WORK/positive/.build/app-store/source-membership.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    audit = json.load(handle)
assert audit["schema_version"] == 2
assert audit["channel"] == "appStore"
assert audit["compiled_sources"] is None
assert audit["swift_file_lists"] == []
assert audit["source_sha"] == "0123456789abcdef0123456789abcdef01234567"
assert len(audit["source_tree_sha256"]) == 64
assert audit["swift_defines"] == ["STATUS_TRIO_APP_STORE"]
assert "AppKit" in audit["linked_frameworks"]
assert "CoreBluetooth" in audit["linked_frameworks"]
PY

make_fixture "$WORK/duplicate-groups"
expect_pass "duplicate-group fixture project generation" \
    run_generator "$WORK/duplicate-groups"
make_duplicate_group_project "$WORK/duplicate-groups"
expect_fail_contains "malformed duplicate PBXGroup membership" \
    "multiple PBXGroups" validate_duplicate_group_project "$WORK/duplicate-groups"

# 2. Missing manifest fails closed.
make_fixture "$WORK/missing-manifest"
/bin/rm -f "$WORK/missing-manifest/AppStore/direct-only-sources.txt"
expect_fail "missing Direct-only manifest" run_generator "$WORK/missing-manifest"

# 3. Escaping path fails closed.
make_fixture "$WORK/path-escape"
printf '../Outside.swift\n' > "$WORK/path-escape/AppStore/direct-only-sources.txt"
expect_fail "path escape in Direct-only manifest" run_generator "$WORK/path-escape"

# 4. A listed nonexistent file fails closed.
make_fixture "$WORK/missing-source"
cat > "$WORK/missing-source/AppStore/direct-only-sources.txt" <<'EOF'
Sources/StatusTrioCore/App/DirectProbe.swift
Sources/StatusTrioCore/App/DoesNotExist.swift
EOF
expect_fail "nonexistent Direct-only source" run_generator "$WORK/missing-source"

# 5. Direct source exclusion is reflected in both audit and Xcode spec.
make_fixture "$WORK/exclusion"
printf '# header\nSources/StatusTrioCore/App/DirectProbe.swift\n' \
    > "$WORK/exclusion/AppStore/direct-only-sources.txt"
expect_pass "Direct source exclusion" run_generator "$WORK/exclusion"
expect_pass "Direct exclusion project assertion" \
    assert_project_safety "$WORK/exclusion"

# 6. Explicit version overrides are validated and propagated.
make_fixture "$WORK/version"
APP_VERSION=2.3.4 BUILD_NUMBER=45 \
    expect_pass "version/build override" run_generator "$WORK/version"
expect_pass "version/build override output" \
    assert_generated_files "$WORK/version" 2.3.4 45

make_fixture "$WORK/bad-version"
APP_VERSION=2.3.beta \
    expect_fail "invalid version override" run_generator "$WORK/bad-version"
make_fixture "$WORK/bad-build"
BUILD_NUMBER=forty \
    expect_fail "invalid build override" run_generator "$WORK/bad-build"
make_fixture "$WORK/bad-sha"
STATUS_TRIO_SOURCE_SHA=ABC \
    expect_fail "invalid frozen source SHA" run_generator "$WORK/bad-sha"

# 7. Sparkle configuration is rejected regardless of source exclusion.
make_fixture "$WORK/sparkle"
printf '// Sparkle must not appear in Store configuration\n' \
    > "$WORK/sparkle/AppStore/Version.xcconfig"
expect_fail "Sparkle configuration marker" run_membership_check "$WORK/sparkle"

# 8. SDK floor is fixed in the spec and the missing-platform scaffold fails.
make_fixture "$WORK/platform-missing"
mv "$WORK/platform-missing/AppStore/Platform" "$WORK/platform-missing/AppStore/Platform.removed"
expect_fail "missing Store platform directory" run_generator "$WORK/platform-missing"

make_fixture "$WORK/accessor-missing"
mv "$WORK/accessor-missing/AppStore/Platform/StoreResourceBundle.swift" \
    "$WORK/accessor-missing/AppStore/Platform/StoreResourceBundle.swift.removed"
expect_fail "missing Store resource accessor" run_generator "$WORK/accessor-missing"

make_fixture "$WORK/app-localization-missing"
mv "$WORK/app-localization-missing/Sources/StatusTrioCore/Resources/ja.lproj/InfoPlist.strings" \
    "$WORK/app-localization-missing/Sources/StatusTrioCore/Resources/ja.lproj/InfoPlist.strings.removed"
expect_fail "missing localized app InfoPlist.strings" \
    run_generator "$WORK/app-localization-missing"

make_fixture "$WORK/app-icon-missing"
mv "$WORK/app-icon-missing/Support/AppIcon.png" \
    "$WORK/app-icon-missing/Support/AppIcon.png.removed"
expect_fail "missing Store app icon source" run_generator "$WORK/app-icon-missing"

make_fixture "$WORK/privacy-missing"
/bin/rm -f "$WORK/privacy-missing/AppStore/PrivacyInfo.xcprivacy"
expect_fail "missing Store privacy manifest" run_generator "$WORK/privacy-missing"

make_fixture "$WORK/privacy-tracking"
/usr/libexec/PlistBuddy -c 'Set :NSPrivacyTracking true' \
    "$WORK/privacy-tracking/AppStore/PrivacyInfo.xcprivacy"
expect_fail "Store privacy tracking enabled" run_generator "$WORK/privacy-tracking"

make_fixture "$WORK/privacy-collected"
/usr/libexec/PlistBuddy -c \
    'Add :NSPrivacyCollectedDataTypes:0 dict' \
    "$WORK/privacy-collected/AppStore/PrivacyInfo.xcprivacy"
expect_fail "Store privacy collected data" run_generator "$WORK/privacy-collected"

make_fixture "$WORK/privacy-tracking-domain"
/usr/libexec/PlistBuddy -c \
    'Add :NSPrivacyTrackingDomains:0 string https://tracking.example.invalid' \
    "$WORK/privacy-tracking-domain/AppStore/PrivacyInfo.xcprivacy"
expect_fail "Store privacy tracking domain" run_generator "$WORK/privacy-tracking-domain"

make_fixture "$WORK/entitlement-missing"
/usr/libexec/PlistBuddy -c \
    "Delete :com.apple.security.device.bluetooth" \
    "$WORK/entitlement-missing/Distribution/AppStore.entitlements"
expect_fail "missing Bluetooth entitlement in template" \
    run_generator "$WORK/entitlement-missing"

make_fixture "$WORK/unexcluded-direct-import"
printf 'import Foundation\nimport Sparkle\nfinal class HiddenDirectProbe {}\n' \
    > "$WORK/unexcluded-direct-import/Sources/StatusTrioCore/App/HiddenDirectProbe.swift"
expect_fail "unexcluded Direct import in shared source" \
    run_generator "$WORK/unexcluded-direct-import"

make_fixture "$WORK/platform-direct-import"
printf 'import Sparkle\nfinal class HiddenStoreProbe {}\n' \
    > "$WORK/platform-direct-import/AppStore/Platform/HiddenStoreProbe.swift"
expect_fail "Store platform source cannot import Direct module" \
    run_generator "$WORK/platform-direct-import"

make_fixture "$WORK/wrong-root"
mkdir -p "$WORK/not-a-repository"
expect_fail "non-repository root rejected" \
    python3 "$WORK/wrong-root/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/not-a-repository" \
    --check-membership-only

# 9. Fixed SDK floor, macOS 13 deployment, and strict concurrency in generated spec.
make_fixture "$WORK/floor"
expect_pass "floor fixture generation" run_generator "$WORK/floor"
python3 - "$WORK/floor/AppStore/project.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    spec = json.load(handle)
base = spec["settings"]["base"]
assert base["MACOSX_DEPLOYMENT_TARGET"] == "13.0"
assert base["SWIFT_VERSION"] == "6.0"
assert base["SWIFT_STRICT_CONCURRENCY"] == "complete"
assert spec["options"]["minimumXcodeGenVersion"] == "2.46.0"
assert spec["configFiles"] == {
    "Debug": "AppStore/Version.xcconfig",
    "Release": "AppStore/Version.xcconfig",
}
assert spec["configs"]["Release"]["DEBUG_INFORMATION_FORMAT"] == "dwarf-with-dsym"
assert spec["configs"]["Release"]["COPY_PHASE_STRIP"] is False
core = spec["targets"]["StatusTrioCore"]["settings"]["base"]
assert core["LD_DYLIB_INSTALL_NAME"] == (
    "@rpath/StatusTrioCore.framework/Versions/A/StatusTrioCore"
)
assert core["DYLIB_INSTALL_NAME_BASE"] == "@rpath"
assert core["LD_RUNPATH_SEARCH_PATHS"].endswith("@loader_path/Frameworks")
PY
expect_pass "fixed platform and Swift settings" true

make_fixture "$WORK/xcodegen-version"
expect_pass "exact XcodeGen version accepted" env XCODEGEN="$XCODEGEN" \
    python3 "$WORK/xcodegen-version/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/xcodegen-version" \
    --check-membership-only --require-xcodegen
cat > "$WORK/fake-xcodegen-newer" <<'SH'
#!/bin/sh
echo "Version: 2.47.0"
SH
chmod +x "$WORK/fake-xcodegen-newer"
expect_fail "newer XcodeGen version rejected by exact pin" env XCODEGEN="$WORK/fake-xcodegen-newer" \
    python3 "$WORK/xcodegen-version/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/xcodegen-version" \
    --check-membership-only --require-xcodegen

# 10. Build-time evidence: actual file lists close included_sources, and
# generated DerivedSources are recorded separately rather than silently
# dropped.
make_fixture "$WORK/compiled"
python3 - "$WORK/compiled/AppStore/direct-only-sources.txt" <<'PY'
import sys

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write("Sources/StatusTrioCore/App/DirectProbe.swift\n")
PY
expect_pass "compiled-source fixture generation" run_generator "$WORK/compiled"
COMPILED_LIST_DIR="$WORK/compiled/.build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrioAppStore.build/Release/StatusTrioCore.build/Objects-normal"
mkdir -p "$COMPILED_LIST_DIR"
FILE_LIST="$COMPILED_LIST_DIR/arm64/StatusTrioCore.SwiftFileList"
X86_FILE_LIST="$COMPILED_LIST_DIR/x86_64/StatusTrioCore.SwiftFileList"
mkdir -p "$(dirname "$FILE_LIST")" "$(dirname "$X86_FILE_LIST")"
printf '%s\n' \
    "$WORK/compiled/AppStore/Platform/StorePlatformProbe.swift" \
    "$WORK/compiled/AppStore/Platform/StoreResourceBundle.swift" \
    "$WORK/compiled/Sources/StatusTrioCore/App/SharedProbe.swift" \
    "$WORK/compiled/Sources/StatusTrioCore/App/MissingShared.swift" \
    | tee "$FILE_LIST" > "$X86_FILE_LIST"
expect_fail "compiled-source mismatch detected" \
    python3 "$WORK/compiled/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/compiled" \
    --record-compiled-sources "$WORK/compiled/.build/app-store/DerivedData" \
    --record-build-action build --record-configuration Release

mkdir -p "$WORK/compiled/.build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrioAppStore.build/Release/StatusTrioCore.build/DerivedSources"
printf '%s\n' \
    "$WORK/compiled/AppStore/Platform/StorePlatformProbe.swift" \
    "$WORK/compiled/AppStore/Platform/StoreResourceBundle.swift" \
    "$WORK/compiled/Sources/StatusTrioCore/App/SharedProbe.swift" \
    "$WORK/compiled/.build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrioAppStore.build/Release/StatusTrioCore.build/DerivedSources/Generated.swift" \
    | tee "$FILE_LIST" > "$X86_FILE_LIST"
expect_pass "compiled-source closure" \
    python3 "$WORK/compiled/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/compiled" \
    --record-compiled-sources "$WORK/compiled/.build/app-store/DerivedData" \
    --record-build-action build --record-configuration Release
expect_pass "closure audit parser accepts actual file lists" \
    python3 "$WORK/compiled/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/compiled" \
    --verify-closure-audit
expect_pass "membership-only check remains non-writing" \
    python3 "$WORK/compiled/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/compiled" \
    --check-membership-only
expect_pass "record and verify can run in one invocation" \
    python3 "$WORK/compiled/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/compiled" \
    --project "$WORK/compiled/AppStore/project.json" \
    --output-root "$WORK/compiled/.build/app-store" \
    --record-compiled-sources "$WORK/compiled/.build/app-store/DerivedData" \
    --record-build-action build --record-configuration Release \
    --verify-closure-audit

SOURCE_TREE_DIGEST="$(
    python3 - "$WORK/compiled/.build/app-store/source-membership.json" <<'PY'
import json
import sys

print(json.load(open(sys.argv[1], encoding="utf-8"))["source_tree_sha256"])
PY
)"
expect_pass "the pre-build source digest still matches" \
    python3 "$WORK/compiled/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/compiled" \
    --record-compiled-sources "$WORK/compiled/.build/app-store/DerivedData" \
    --record-build-action build --record-configuration Release \
    --expected-source-tree-sha256 "$SOURCE_TREE_DIGEST" \
    --verify-closure-audit
printf '\n// changed after the build\n' \
    >> "$WORK/compiled/Sources/StatusTrioCore/App/SharedProbe.swift"
expect_fail_contains "source changes during the build are rejected" \
    "Store source tree changed during the build" \
    python3 "$WORK/compiled/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/compiled" \
    --record-compiled-sources "$WORK/compiled/.build/app-store/DerivedData" \
    --record-build-action build --record-configuration Release \
    --expected-source-tree-sha256 "$SOURCE_TREE_DIGEST" \
    --verify-closure-audit
expect_fail_contains "archive action cannot select build evidence" \
    "missing StoreCore SwiftFileList for archive/Release/arm64" \
    python3 "$WORK/compiled/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/compiled" \
    --record-compiled-sources "$WORK/compiled/.build/app-store/DerivedData" \
    --record-build-action archive --record-configuration Release

# Stale evidence from the other build action must not be selected for this
# invocation, while a duplicate within the selected action remains fatal.
STALE_ARCHIVE_DIR="$WORK/compiled/.build/app-store/DerivedData/Build/Intermediates.noindex/ArchiveIntermediates/StatusTrioAppStore/IntermediateBuildFilesPath/StatusTrioAppStore.build/Release/StatusTrioCore.build/Objects-normal"
mkdir -p "$STALE_ARCHIVE_DIR/arm64" "$STALE_ARCHIVE_DIR/x86_64"
printf '%s\n' "$WORK/compiled/Sources/StatusTrioCore/App/Stale.swift" \
    | tee "$STALE_ARCHIVE_DIR/arm64/StatusTrioCore.SwiftFileList" \
    > "$STALE_ARCHIVE_DIR/x86_64/StatusTrioCore.SwiftFileList"
expect_pass "stale archive evidence is ignored for build" \
    python3 "$WORK/compiled/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/compiled" \
    --project "$WORK/compiled/AppStore/project.json" \
    --output-root "$WORK/compiled/.build/app-store" \
    --record-compiled-sources "$WORK/compiled/.build/app-store/DerivedData" \
    --record-build-action build --record-configuration Release \
    --verify-closure-audit
cp -R "$WORK/compiled" "$WORK/compiled-duplicate"
SECOND_ARCHIVE_DIR="$WORK/compiled-duplicate/.build/app-store/DerivedData/Build/Intermediates.noindex/ArchiveIntermediates/StatusTrioAppStoreSecond/IntermediateBuildFilesPath/StatusTrioAppStore.build/Release/StatusTrioCore.build/Objects-normal"
mkdir -p "$SECOND_ARCHIVE_DIR/arm64" "$SECOND_ARCHIVE_DIR/x86_64"
cp "$WORK/compiled-duplicate/.build/app-store/DerivedData/Build/Intermediates.noindex/ArchiveIntermediates/StatusTrioAppStore/IntermediateBuildFilesPath/StatusTrioAppStore.build/Release/StatusTrioCore.build/Objects-normal/arm64/StatusTrioCore.SwiftFileList" \
    "$SECOND_ARCHIVE_DIR/arm64/StatusTrioCore.SwiftFileList"
cp "$WORK/compiled-duplicate/.build/app-store/DerivedData/Build/Intermediates.noindex/ArchiveIntermediates/StatusTrioAppStore/IntermediateBuildFilesPath/StatusTrioAppStore.build/Release/StatusTrioCore.build/Objects-normal/x86_64/StatusTrioCore.SwiftFileList" \
    "$SECOND_ARCHIVE_DIR/x86_64/StatusTrioCore.SwiftFileList"
expect_fail_contains "duplicate current-action evidence fails closed" "duplicate StoreCore SwiftFileList" \
    python3 "$WORK/compiled-duplicate/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/compiled-duplicate" \
    --record-compiled-sources "$WORK/compiled-duplicate/.build/app-store/DerivedData" \
    --record-build-action archive --record-configuration Release
/bin/rm -rf "$WORK/compiled-duplicate"
expect_pass "derived source is separated in audit" \
    python3 - "$WORK/compiled/.build/app-store/source-membership.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    audit = json.load(handle)
assert audit["compiled_sources"] == audit["included_sources"]
assert audit["derived_sources"] == [
    ".build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrioAppStore.build/Release/StatusTrioCore.build/DerivedSources/Generated.swift"
]
assert len(audit["swift_file_lists"]) == 2
assert audit["swift_file_lists"][0].startswith(".build/app-store/DerivedData/")
PY

# 11. A target with no generated Swift is valid; DerivedSources must not be
# invented just to satisfy the collector.
make_fixture "$WORK/no-derived"
expect_pass "no-derived fixture generation" run_generator "$WORK/no-derived"
mkdir -p \
    "$WORK/no-derived/.build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrioAppStore.build/Release/StatusTrioCore.build/Objects-normal/arm64" \
    "$WORK/no-derived/.build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrioAppStore.build/Release/StatusTrioCore.build/Objects-normal/x86_64"
NO_DERIVED_FILE_LIST="$WORK/no-derived/.build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrioAppStore.build/Release/StatusTrioCore.build/Objects-normal/arm64/StatusTrioCore.SwiftFileList"
NO_DERIVED_X86_FILE_LIST="$WORK/no-derived/.build/app-store/DerivedData/Build/Intermediates.noindex/StatusTrioAppStore.build/Release/StatusTrioCore.build/Objects-normal/x86_64/StatusTrioCore.SwiftFileList"
printf '%s\n' \
    "$WORK/no-derived/AppStore/Platform/StorePlatformProbe.swift" \
    "$WORK/no-derived/AppStore/Platform/StoreResourceBundle.swift" \
    "$WORK/no-derived/Sources/StatusTrioCore/App/SharedProbe.swift" \
    | tee "$NO_DERIVED_FILE_LIST" > "$NO_DERIVED_X86_FILE_LIST"
expect_pass "no generated Swift sources is valid" \
    python3 "$WORK/no-derived/scripts/generate-app-store-project.py" \
    --repo-root "$WORK/no-derived" \
    --record-compiled-sources "$WORK/no-derived/.build/app-store/DerivedData" \
    --record-build-action build --record-configuration Release \
    --verify-closure-audit
expect_pass "no-derived audit records an empty derived_sources" \
    python3 - "$WORK/no-derived/.build/app-store/source-membership.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    audit = json.load(handle)
assert audit["compiled_sources"] == audit["included_sources"]
assert audit["derived_sources"] == [], audit["derived_sources"]
assert len(audit["swift_file_lists"]) == 2
PY

# 12. Generated PBX must contain real resource build phases. XcodeGen ignores
# a target-level `resources` key, so assert the generated project itself.
make_fixture "$WORK/pbx-resources"
expect_pass "PBX resource fixture generation" run_generator "$WORK/pbx-resources"
PBX_PROJECT_DIR="$WORK/pbx-resources/.build/app-store/XcodeProject"
mkdir -p "$PBX_PROJECT_DIR"
expect_pass "PBX resource fixture xcodegen parse" \
    "$XCODEGEN" generate \
    --spec "$WORK/pbx-resources/AppStore/project.json" \
    --project "$PBX_PROJECT_DIR" \
    --project-root "$WORK/pbx-resources" \
    --quiet
expect_pass "PBX has app and Core resource phases" python3 - \
    "$PBX_PROJECT_DIR/StatusTrioAppStore.xcodeproj/project.pbxproj" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
assert text.count("/* Begin PBXResourcesBuildPhase section */") == 1, text
assert len(re.findall(r"isa = PBXResourcesBuildPhase;", text)) == 2, text
assert len(re.findall(
    r"/\* InfoPlist\.strings in Resources \*/ = \{isa = PBXBuildFile;",
    text,
)) == 24, text
assert "/* StatusTrioAppStore.icns in Resources */" in text
assert "/* PrivacyInfo.xcprivacy in Resources */" in text
assert "/* Localizable.strings in Resources */" in text
PY
expect_pass "PBX resources are attached to both targets" python3 - \
    "$PBX_PROJECT_DIR/StatusTrioAppStore.xcodeproj/project.pbxproj" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
resource_ids = {}
for match in re.finditer(
    r"([0-9A-F]{24}) /\* ([^*]+) in Resources \*/ = \{isa = PBXBuildFile;",
    text,
):
    resource_ids.setdefault(match.group(2), []).append(match.group(1))
assert sum(len(ids) for ids in resource_ids.values()) == 27, resource_ids
assert len(resource_ids.get("InfoPlist.strings", [])) == 24, resource_ids
assert len(resource_ids.get("PrivacyInfo.xcprivacy", [])) == 1, resource_ids
phases = re.findall(
    r"([0-9A-F]{24}) /\* Resources \*/ = \{\s*isa = PBXResourcesBuildPhase;(.*?)\};",
    text,
    re.DOTALL,
)
assert len(phases) == 2, phases
phase_bodies = {phase_id: body for phase_id, body in phases}
targets = re.findall(
    r"([0-9A-F]{24}) /\* (StatusTrio(?:Core)?) \*/ = \{\s*isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);",
    text,
    re.DOTALL,
)
assert len(targets) == 2, targets
by_target = {
    name: re.findall(r"([0-9A-F]{24}) /\* Resources \*/", phases_text)
    for _, name, phases_text in targets
}
assert set(by_target) == {"StatusTrio", "StatusTrioCore"}, by_target
app_phase = by_target["StatusTrio"][0]
core_phase = by_target["StatusTrioCore"][0]
assert app_phase in phase_bodies and core_phase in phase_bodies
app_body = phase_bodies[app_phase]
core_body = phase_bodies[core_phase]
assert "InfoPlist.strings in Resources" in app_body
assert "StatusTrioAppStore.icns in Resources" in app_body
assert "PrivacyInfo.xcprivacy in Resources" in app_body
assert "Localizable.strings in Resources" in core_body
assert "StatusTrioAppStore.icns in Resources" not in core_body
assert "PrivacyInfo.xcprivacy in Resources" not in core_body
PY

if [[ "$PASSES" -ne "$CASES" ]]; then
    fail "expected every offline case to pass"
fi
printf '\nOffline App Store project contract: %d/%d PASS\n' "$PASSES" "$CASES"

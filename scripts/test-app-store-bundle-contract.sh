#!/usr/bin/env bash
# Offline contract tests for verify-app-store-bundle.sh.
#
# Every fixture is synthetic. PATH shims stand in for file, codesign, otool,
# and nm so these tests do not inspect the host, request permissions, read
# signing credentials, or launch an app.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIER="$ROOT/scripts/verify-app-store-bundle.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioAppStoreAudit.XXXXXX")"
SHIMS="$WORK/shims"
SCENARIOS=0
SCENARIOS_PASSED=0
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "App Store bundle contract failed: $*" >&2
    exit 1
}

if [[ ! -f "$VERIFIER" || ! -f "$ROOT/scripts/app-store-bundle-audit.py" ]]; then
    fail "missing verifier or auditor under $ROOT/scripts"
fi

mkdir -p "$SHIMS"

cat > "$SHIMS/file" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MOCK_FILE_FAIL:-0}" == "1" ]]; then
    echo "file: simulated failure" >&2
    exit 1
fi
path=""
for arg in "$@"; do
    path="$arg"
done
if [[ ! -f "$path" || ! -r "$path" ]]; then
    echo "file: cannot read $path" >&2
    exit 1
fi
magic="$(/usr/bin/head -c 4 "$path" | /usr/bin/od -An -tx1 | /usr/bin/tr -d '[:space:]')"
case "$magic" in
    cffaedfe|feedfacf|cefaedfe|feedface|cafebabe|bebafeca|cafebabf|bfbafeca)
        echo "Mach-O 64-bit executable arm64"
        ;;
    *)
        echo "ASCII text"
        ;;
esac
SH
chmod +x "$SHIMS/file"

cat > "$SHIMS/codesign" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${MOCK_CODESIGN_LOG:-}" ]]; then
    printf '%s\n' "$*" >> "$MOCK_CODESIGN_LOG"
fi
app=""
for arg in "$@"; do
    app="$arg"
done
args=" $* "
case "$args" in
    *" --verify "*)
        if [[ -e "$app.fixture-verify-fail" ]]; then
            echo "codesign: simulated verification failure" >&2
            exit 1
        fi
        if [[ -f "$app.fixture-verify-calls" ]]; then
            target="$(cd -- "$(dirname -- "$app")" && pwd)/$(basename -- "$app")"
            printf '%s\n' "$target" >> "$app.fixture-verify-calls"
        fi
        exit 0
        ;;
    *" --entitlements "*)
        if [[ -e "$app.fixture-entitlements-fail" ]]; then
            echo "codesign: simulated entitlement read failure" >&2
            exit 1
        fi
        printf 'Executable=%s/Contents/MacOS/StatusTrio\n' "$app"
        if [[ -f "$app.fixture-entitlements" ]]; then
            cat "$app.fixture-entitlements"
        fi
        exit 0
        ;;
esac
echo "codesign: unexpected invocation: $*" >&2
exit 2
SH
chmod +x "$SHIMS/codesign"

cat > "$SHIMS/otool" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MOCK_OTOOL_FAIL:-0}" == "1" ]]; then
    echo "otool: simulated failure" >&2
    exit 1
fi
path=""
for arg in "$@"; do
    path="$arg"
done
if [[ -f "$path.fixture-otool" ]]; then
    cat "$path.fixture-otool"
else
    printf '%s:\n' "$path"
    printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
fi
SH
chmod +x "$SHIMS/otool"

cat > "$SHIMS/nm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MOCK_NM_FAIL:-0}" == "1" ]]; then
    echo "nm: simulated failure" >&2
    exit 1
fi
mode=""
global_only=0
path=""
for arg in "$@"; do
    case "$arg" in
        -u|-a) mode="$arg" ;;
        -g|-j|-gj|-jg) global_only=1 ;;
        -*) ;;
        *) path="$arg" ;;
    esac
done
if [[ "$global_only" == "1" && "${MOCK_NM_GLOBAL_EMPTY_FAIL:-0}" == "1" ]]; then
    exit 1
fi
if [[ "$global_only" == "1" ]]; then
    if [[ -f "$path.fixture-objc-symbols" ]]; then
        cat "$path.fixture-objc-symbols"
    fi
elif [[ "$mode" == "-u" && -f "$path.fixture-nm" ]]; then
    cat "$path.fixture-nm"
elif [[ "$mode" == "-a" && -f "$path.fixture-nm-all" ]]; then
    cat "$path.fixture-nm-all"
elif [[ -z "$mode" ]]; then
    echo "nm: expected -u, -a, or global symbol mode" >&2
    exit 2
fi
SH
chmod +x "$SHIMS/nm"

run_audit() {
    PATH="$SHIMS:$PATH" bash "$VERIFIER" "$@"
}

expect_pass() {
    local label="$1"
    shift
    SCENARIOS=$((SCENARIOS + 1))
    if ! "$@" >"$WORK/last.stdout" 2>"$WORK/last.stderr"; then
        cat "$WORK/last.stdout" >&2
        cat "$WORK/last.stderr" >&2
        fail "$label was rejected"
    fi
    if grep -Fq 'Error:' "$WORK/last.stderr"; then
        cat "$WORK/last.stderr" >&2
        fail "$label emitted an audit error despite being accepted"
    fi
    SCENARIOS_PASSED=$((SCENARIOS_PASSED + 1))
    printf 'PASS %02d: %s\n' "$SCENARIOS" "$label"
}

expect_rejected() {
    local label="$1"
    shift
    SCENARIOS=$((SCENARIOS + 1))
    if "$@" >"$WORK/last.stdout" 2>"$WORK/last.stderr"; then
        cat "$WORK/last.stdout" >&2
        fail "$label was accepted"
    fi
    SCENARIOS_PASSED=$((SCENARIOS_PASSED + 1))
    printf 'PASS %02d: %s\n' "$SCENARIOS" "$label"
}

write_info() {
    local root="$1"
    local bundle_id="${2:-com.lingsmbp.StatusTrio.AppStore}"
    cat > "$root/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>StatusTrio</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_id</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.7.0</string>
    <key>CFBundleVersion</key>
    <string>38</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST
}

macho_slice_bytes() {
    local filetype="$1"
    local filetype_bytes
    case "$filetype" in
        2) filetype_bytes='\002\000\000\000' ;;
        6) filetype_bytes='\006\000\000\000' ;;
        *) fail "unsupported synthetic Mach-O filetype: $filetype" ;;
    esac
    printf '\317\372\355\376\014\000\000\001\000\000\000\000'
    printf '%b' "$filetype_bytes"
    printf '\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000'
}

make_macho() {
    local path="$1"
    local filetype="${2:-2}"
    mkdir -p "$(dirname -- "$path")"
    macho_slice_bytes "$filetype" > "$path"
}

make_universal_macho() {
    local path="$1"
    local first_type="$2"
    local second_type="$3"
    mkdir -p "$(dirname -- "$path")"
    {
        printf '\312\376\272\276\000\000\000\002'
        printf '\001\000\000\007\000\000\000\003\000\000\000\060\000\000\000\040\000\000\000\014'
        printf '\001\000\000\014\000\000\000\000\000\000\000\120\000\000\000\040\000\000\000\014'
        macho_slice_bytes "$first_type"
        macho_slice_bytes "$second_type"
    } > "$path"
}

make_app() {
    local name="$1"
    local bundle_id="${2:-com.lingsmbp.StatusTrio.AppStore}"
    local root="$WORK/$name"
    mkdir -p \
        "$root/Contents/MacOS" \
        "$root/Contents/Resources" \
        "$root/Contents/Frameworks/Public.framework/Versions/A"
    write_info "$root" "$bundle_id"
    make_macho "$root/Contents/MacOS/StatusTrio"
    chmod +x "$root/Contents/MacOS/StatusTrio"
    make_macho "$root/Contents/Frameworks/Public.framework/Versions/A/Public" 6
    ln -s A "$root/Contents/Frameworks/Public.framework/Versions/Current"
    ln -s Versions/Current/Public "$root/Contents/Frameworks/Public.framework/Public"
    printf 'Status Trio App Store audit fixture.\n' > "$root/Contents/Resources/README.txt"
    echo "$root"
}

write_clean_entitlements() {
    local root="$1"
    mkdir -p "$root/Contents/MacOS"
    cat > "$root.fixture-entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
PLIST
    cp "$root.fixture-entitlements" "$root/Contents/MacOS/StatusTrio.fixture-entitlements"
}

write_nested_entitlements() {
    local component="$1"
    local body="${2:-    <key>com.apple.security.app-sandbox</key>
    <true/>}"
    cat > "$component.fixture-entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$body
</dict>
</plist>
PLIST
}

write_entitlements() {
    local root="$1"
    local body="$2"
    mkdir -p "$root/Contents/MacOS"
    cat > "$root.fixture-entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$body
</dict>
</plist>
PLIST
    cp "$root.fixture-entitlements" "$root/Contents/MacOS/StatusTrio.fixture-entitlements"
}

# 1. Positive control: a signed Store bundle with a nested public Mach-O.
make_app clean-signed >/dev/null
write_clean_entitlements "$WORK/clean-signed"
cp "$WORK/clean-signed.fixture-entitlements" \
    "$WORK/clean-signed/Contents/MacOS/StatusTrio.fixture-entitlements"
clean_signed_path="$(cd "$WORK/clean-signed" && pwd -P)"
signed_clean_log="$WORK/signed-clean-codesign.log"
expect_pass "signed clean bundle" \
    env MOCK_CODESIGN_LOG="$signed_clean_log" PATH="$SHIMS:$PATH" \
    bash "$VERIFIER" "$WORK/clean-signed"
for container in Frameworks Resources; do
    if grep -Fxq -- "--verify --strict --verbose=2 $clean_signed_path/Contents/$container" \
        "$signed_clean_log"; then
        fail "codesign treated Contents/$container as a code item"
    fi
done

# 2. Signed public frameworks need not carry the app sandbox entitlement, but
# every nested code item still has to be recursively verified.
make_app clean-public-framework >/dev/null
write_clean_entitlements "$WORK/clean-public-framework"
cp "$WORK/clean-public-framework.fixture-entitlements" \
    "$WORK/clean-public-framework/Contents/MacOS/StatusTrio.fixture-entitlements"
clean_public_path="$(cd "$WORK/clean-public-framework" && pwd -P)"
PUBLIC_FRAMEWORK="$WORK/clean-public-framework/Contents/Frameworks/Public.framework"
PUBLIC_FRAMEWORK_REAL="$clean_public_path/Contents/Frameworks/Public.framework"
write_nested_entitlements "$PUBLIC_FRAMEWORK" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
VERIFY_LOG="$WORK/recursive-codesign.log"
expect_pass "signed public framework without sandbox entitlement" \
    env MOCK_CODESIGN_LOG="$VERIFY_LOG" PATH="$SHIMS:$PATH" \
    bash "$VERIFIER" "$WORK/clean-public-framework"
grep -Fxq -- "--verify --strict --verbose=2 $clean_public_path/Contents/MacOS/StatusTrio" \
    "$VERIFY_LOG" ||
    fail "codesign did not verify the main executable"
grep -Fxq -- "--verify --strict --verbose=2 $PUBLIC_FRAMEWORK_REAL" \
    "$VERIFY_LOG" ||
    fail "codesign did not verify the nested public framework"
grep -Fxq -- "-d --entitlements :- $PUBLIC_FRAMEWORK_REAL" \
    "$VERIFY_LOG" ||
    fail "codesign did not read nested framework entitlements"
grep -Fxq -- "--verify --strict --verbose=2 $PUBLIC_FRAMEWORK_REAL/Versions/A/Public" \
    "$VERIFY_LOG" ||
    fail "codesign did not verify the framework Mach-O"
for item in \
    "$clean_public_path" \
    "$clean_public_path/Contents/MacOS/StatusTrio" \
    "$PUBLIC_FRAMEWORK_REAL" \
    "$PUBLIC_FRAMEWORK_REAL/Versions/A/Public"; do
    grep -Fxq -- "-d --entitlements :- $item" "$VERIFY_LOG" ||
        fail "codesign did not inspect entitlements for $item"
done

# 4. A PowerHelper-named nested LaunchAgent is rejected even without a binary.
make_app named-launch-daemon >/dev/null
write_clean_entitlements "$WORK/named-launch-daemon"
mkdir -p "$WORK/named-launch-daemon/Contents/Library/LaunchAgents"
printf '<plist version="1.0"><dict/></plist>\n' \
    > "$WORK/named-launch-daemon/Contents/Library/LaunchAgents/com.lingsmbp.StatusTrio.PowerHelper.plist"
expect_rejected "PowerHelper LaunchAgent name" run_audit "$WORK/named-launch-daemon"

# 5. Unsigned mode must skip codesign and say exactly what it proved.
make_app clean-unsigned >/dev/null
printf 'this marker makes signed verification fail\n' > "$WORK/clean-unsigned.fixture-verify-fail"
UNSIGNED_LOG="$WORK/unsigned-codesign.log"
expect_pass "unsigned clean bundle" \
    env MOCK_CODESIGN_LOG="$UNSIGNED_LOG" PATH="$SHIMS:$PATH" \
    bash "$VERIFIER" "$WORK/clean-unsigned" --unsigned
grep -Fq 'unsigned compile/static only' "$WORK/last.stdout" ||
    fail "unsigned result did not identify the static-only scope"
grep -Fq 'Sandbox runtime: NOT RUN' "$WORK/last.stdout" ||
    fail "unsigned result did not mark sandbox runtime as not run"
[[ ! -e "$UNSIGNED_LOG" ]] || fail "unsigned mode invoked codesign"

# 6. Ordinary resource copy may mention Sparkle or SU metadata.
make_app sparkle-resource >/dev/null
write_clean_entitlements "$WORK/sparkle-resource"
printf 'Sparkle is not used in this edition. SUFeedURL is documentation only.\n' \
    > "$WORK/sparkle-resource/Contents/Resources/Credits.txt"
expect_pass "resource text mentions Sparkle" run_audit "$WORK/sparkle-resource"

# 7. A property list's data value is still scan-relevant even though arbitrary
# replacement resources are allowed to contain documentation text.
make_app plist-sparkle-data >/dev/null
write_clean_entitlements "$WORK/plist-sparkle-data"
cat > "$WORK/plist-sparkle-data/Contents/Resources/Embedded.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Payload</key>
    <data>U1BVVXBkYXRlcg==</data>
</dict>
</plist>
PLIST
expect_rejected "Sparkle symbol in plist data value" run_audit "$WORK/plist-sparkle-data"

# 7. Explicit Store development identity is accepted.
make_app store-dev com.lingsmbp.StatusTrio.AppStore.dev.audit >/dev/null
write_clean_entitlements "$WORK/store-dev"
expect_pass "Store development bundle id" run_audit "$WORK/store-dev"

# 8-9. Direct and unrelated suffix identities are rejected.
make_app direct-id com.lingsmbp.StatusTrio >/dev/null
write_clean_entitlements "$WORK/direct-id"
expect_rejected "Direct bundle id" run_audit "$WORK/direct-id"

make_app unrelated-suffix com.lingsmbp.StatusTrio.AppStore.evil >/dev/null
write_clean_entitlements "$WORK/unrelated-suffix"
expect_rejected "unrelated bundle id suffix" run_audit "$WORK/unrelated-suffix"

# 10-11. SU metadata is rejected in Info.plist and in a nested plist.
make_app info-sparkle >/dev/null
write_clean_entitlements "$WORK/info-sparkle"
/usr/libexec/PlistBuddy -c \
    'Add :SUFeedURL string https://example.invalid/appcast.xml' \
    "$WORK/info-sparkle/Contents/Info.plist"
expect_rejected "SUFeedURL in Info.plist" run_audit "$WORK/info-sparkle"

make_app nested-sparkle-plist >/dev/null
write_clean_entitlements "$WORK/nested-sparkle-plist"
cat > "$WORK/nested-sparkle-plist/Contents/Resources/Settings.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
</dict>
</plist>
PLIST
expect_rejected "SU key in nested plist" run_audit "$WORK/nested-sparkle-plist"

# 12-16. Direct-only components are rejected at any depth.
make_app sparkle-framework >/dev/null
write_clean_entitlements "$WORK/sparkle-framework"
make_macho "$WORK/sparkle-framework/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
expect_rejected "nested Sparkle.framework" run_audit "$WORK/sparkle-framework"

make_app ddc-component >/dev/null
write_clean_entitlements "$WORK/ddc-component"
make_macho "$WORK/ddc-component/Contents/Frameworks/DDCPrivateAPI.framework/DDCPrivateAPI"
expect_rejected "DDCPrivateAPI component" run_audit "$WORK/ddc-component"

make_app power-helper >/dev/null
write_clean_entitlements "$WORK/power-helper"
make_macho "$WORK/power-helper/Contents/Helpers/StatusTrioPowerHelper"
chmod +x "$WORK/power-helper/Contents/Helpers/StatusTrioPowerHelper"
expect_rejected "StatusTrioPowerHelper" run_audit "$WORK/power-helper"

make_app launch-daemon >/dev/null
write_clean_entitlements "$WORK/launch-daemon"
mkdir -p "$WORK/launch-daemon/Contents/Library/LaunchDaemons"
cat > "$WORK/launch-daemon/Contents/Library/LaunchDaemons/com.lingsmbp.StatusTrio.PowerHelper.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lingsmbp.StatusTrio.PowerHelper</string>
    <key>BundleProgram</key>
    <string>Contents/Helpers/StatusTrioPowerHelper</string>
</dict>
</plist>
PLIST
expect_rejected "root LaunchDaemon registration" run_audit "$WORK/launch-daemon"

make_app mobile-helper >/dev/null
write_clean_entitlements "$WORK/mobile-helper"
make_macho "$WORK/mobile-helper/Contents/Helpers/StatusTrioMobileBatteryHelper"
expect_rejected "mobile battery helper" run_audit "$WORK/mobile-helper"

# Static checks stay active in unsigned mode, including a forbidden framework
# root without any Mach-O whose path could otherwise be overlooked.
make_app unsigned-sparkle >/dev/null
make_macho "$WORK/unsigned-sparkle/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
expect_rejected "unsigned mode with Sparkle.framework" \
    env PATH="$SHIMS:$PATH" bash "$VERIFIER" "$WORK/unsigned-sparkle" --unsigned
make_app path-only-core-display >/dev/null
write_clean_entitlements "$WORK/path-only-core-display"
mkdir -p "$WORK/path-only-core-display/Contents/Frameworks/CoreDisplay.framework"
expect_rejected "CoreDisplay.framework path without Mach-O" \
    env PATH="$SHIMS:$PATH" bash "$VERIFIER" "$WORK/path-only-core-display" --unsigned

# Main, nested, and dependency symbol graphs are all inspected. CoreDisplay is
# private even when it only appears in a symbol table or raw dlsym string.
make_app main-private-symbol >/dev/null
write_clean_entitlements "$WORK/main-private-symbol"
printf '                 U _IOAVServiceReadI2C\n' \
    > "$WORK/main-private-symbol/Contents/MacOS/StatusTrio.fixture-nm"
expect_rejected "private symbol in main Mach-O" run_audit "$WORK/main-private-symbol"

make_app core-display-main-undefined >/dev/null
write_clean_entitlements "$WORK/core-display-main-undefined"
printf '                 U _CoreDisplayCreateDisplay\n' \
    > "$WORK/core-display-main-undefined/Contents/MacOS/StatusTrio.fixture-nm"
expect_rejected "CoreDisplay undefined symbol in main Mach-O" \
    run_audit "$WORK/core-display-main-undefined"

make_app core-display-nested-all-symbol >/dev/null
write_clean_entitlements "$WORK/core-display-nested-all-symbol"
printf '0000000100000000 T _CoreDisplayRegisterClient\n' \
    > "$WORK/core-display-nested-all-symbol/Contents/Frameworks/Public.framework/Versions/A/Public.fixture-nm-all"
expect_rejected "CoreDisplay symbol in nested Mach-O" \
    run_audit "$WORK/core-display-nested-all-symbol"

make_app core-display-main-raw >/dev/null
write_clean_entitlements "$WORK/core-display-main-raw"
printf 'dlsym\000CoreDisplay\000' \
    >> "$WORK/core-display-main-raw/Contents/MacOS/StatusTrio"
expect_rejected "CoreDisplay raw string in main Mach-O" \
    run_audit "$WORK/core-display-main-raw"

make_app core-display-nested-raw >/dev/null
write_clean_entitlements "$WORK/core-display-nested-raw"
printf 'dlsym\000CoreDisplay\000' \
    >> "$WORK/core-display-nested-raw/Contents/Frameworks/Public.framework/Versions/A/Public"
expect_rejected "CoreDisplay raw string in nested Mach-O" \
    run_audit "$WORK/core-display-nested-raw"

make_app core-display-resource-copy >/dev/null
write_clean_entitlements "$WORK/core-display-resource-copy"
printf 'CoreDisplay is not linked or called by this edition.\n' \
    > "$WORK/core-display-resource-copy/Contents/Resources/Credits.txt"
expect_pass "CoreDisplay resource documentation text" \
    run_audit "$WORK/core-display-resource-copy"

make_app nested-dlsym >/dev/null
write_clean_entitlements "$WORK/nested-dlsym"
printf 'dlsym\000IOBluetoothPreferenceGetControllerPower\000' \
    >> "$WORK/nested-dlsym/Contents/Frameworks/Public.framework/Versions/A/Public"
expect_rejected "private dlsym string in nested Mach-O" run_audit "$WORK/nested-dlsym"

make_app local-device-set-power-symbol >/dev/null
write_clean_entitlements "$WORK/local-device-set-power-symbol"
printf '                 U _IOBluetoothLocalDeviceSetPowerState\n' \
    > "$WORK/local-device-set-power-symbol/Contents/MacOS/StatusTrio.fixture-nm"
expect_rejected "IOBluetoothLocalDeviceSetPowerState undefined symbol" \
    run_audit "$WORK/local-device-set-power-symbol"

make_app local-device-supports-power-off-symbol >/dev/null
write_clean_entitlements "$WORK/local-device-supports-power-off-symbol"
printf '                 U _IOBluetoothLocalDeviceSupportsPowerOff\n' \
    > "$WORK/local-device-supports-power-off-symbol/Contents/MacOS/StatusTrio.fixture-nm"
expect_rejected "IOBluetoothLocalDeviceSupportsPowerOff undefined symbol" \
    run_audit "$WORK/local-device-supports-power-off-symbol"

make_app local-device-set-power-dlsym >/dev/null
write_clean_entitlements "$WORK/local-device-set-power-dlsym"
printf 'dlsym\000IOBluetoothLocalDeviceSetPowerState\000' \
    >> "$WORK/local-device-set-power-dlsym/Contents/MacOS/StatusTrio"
expect_rejected "IOBluetoothLocalDeviceSetPowerState dlsym string" \
    run_audit "$WORK/local-device-set-power-dlsym"

make_app local-device-supports-power-off-dlsym >/dev/null
write_clean_entitlements "$WORK/local-device-supports-power-off-dlsym"
printf 'dlsym\000IOBluetoothLocalDeviceSupportsPowerOff\000' \
    >> "$WORK/local-device-supports-power-off-dlsym/Contents/MacOS/StatusTrio"
expect_rejected "IOBluetoothLocalDeviceSupportsPowerOff dlsym string" \
    run_audit "$WORK/local-device-supports-power-off-dlsym"

make_app root-helper-service-label >/dev/null
write_clean_entitlements "$WORK/root-helper-service-label"
printf 'NSXPCListener\000com.lingsmbp.StatusTrio.PowerHelper\000' \
    >> "$WORK/root-helper-service-label/Contents/MacOS/StatusTrio"
expect_rejected "root helper Mach service label in Mach-O" \
    run_audit "$WORK/root-helper-service-label"

make_app ordinary-helper-wording >/dev/null
write_clean_entitlements "$WORK/ordinary-helper-wording"
printf 'NSXPCListener\000com.example.NSXPCService\000com.example.user-visible-helper\000' \
    >> "$WORK/ordinary-helper-wording/Contents/MacOS/StatusTrio"
expect_pass "ordinary helper and NSXPC wording" \
    run_audit "$WORK/ordinary-helper-wording"

make_app private-dependency >/dev/null
write_clean_entitlements "$WORK/private-dependency"
cat > "$WORK/private-dependency/Contents/MacOS/StatusTrio.fixture-otool" <<'OTOOL'
Contents/MacOS/StatusTrio:
	@rpath/DDCPrivateAPI.framework/Versions/A/DDCPrivateAPI (compatibility version 1.0.0, current version 1.0.0)
OTOOL
expect_rejected "private dependency in otool graph" run_audit "$WORK/private-dependency"

# 21-27. Signed entitlements are parsed as a plist and fail closed.
make_app missing-sandbox >/dev/null
write_entitlements "$WORK/missing-sandbox" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
expect_rejected "missing sandbox entitlement" run_audit "$WORK/missing-sandbox"

make_app sandbox-false >/dev/null
write_entitlements "$WORK/sandbox-false" \
    '    <key>com.apple.security.app-sandbox</key>
    <false/>'
expect_rejected "app-sandbox=false" run_audit "$WORK/sandbox-false"

make_app get-task-allow >/dev/null
write_entitlements "$WORK/get-task-allow" \
    '    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.get-task-allow</key>
    <true/>'
expect_rejected "get-task-allow=true" run_audit "$WORK/get-task-allow"

make_app get-task-allow-false >/dev/null
write_entitlements "$WORK/get-task-allow-false" \
    '    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.get-task-allow</key>
    <false/>'
expect_pass "get-task-allow=false" run_audit "$WORK/get-task-allow-false"

make_app temporary-exception >/dev/null
write_entitlements "$WORK/temporary-exception" \
    '    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array>
        <string>com.example.private-service</string>
    </array>'
expect_rejected "temporary sandbox exception" run_audit "$WORK/temporary-exception"

make_app root-entitlement >/dev/null
write_entitlements "$WORK/root-entitlement" \
    '    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.cs.debugger</key>
    <true/>'
expect_rejected "root/debugger entitlement" run_audit "$WORK/root-entitlement"

make_app inherit-entitlement >/dev/null
write_entitlements "$WORK/inherit-entitlement" \
    '    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.inherit</key>
    <true/>'
expect_rejected "inherited sandbox entitlement" run_audit "$WORK/inherit-entitlement"

make_app library-validation-entitlement >/dev/null
write_entitlements "$WORK/library-validation-entitlement" \
    '    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>'
expect_rejected "library-validation escape entitlement" \
    run_audit "$WORK/library-validation-entitlement"

make_app malformed-entitlements >/dev/null
printf 'not a property list\n' > "$WORK/malformed-entitlements.fixture-entitlements"
expect_rejected "malformed entitlements plist" run_audit "$WORK/malformed-entitlements"

make_app absent-entitlements >/dev/null
expect_rejected "main missing entitlements output" run_audit "$WORK/absent-entitlements"

make_app app-root-absent-entitlements >/dev/null
write_clean_entitlements "$WORK/app-root-absent-entitlements"
unlink "$WORK/app-root-absent-entitlements.fixture-entitlements"
expect_rejected "app root missing entitlements output" \
    run_audit "$WORK/app-root-absent-entitlements"

make_app nested-absent-entitlements >/dev/null
write_clean_entitlements "$WORK/nested-absent-entitlements"
expect_pass "nested framework without entitlements" \
    run_audit "$WORK/nested-absent-entitlements"

# 28-34. Direct-only nested components and every signed code item fail closed.
make_app core-display-framework >/dev/null
write_clean_entitlements "$WORK/core-display-framework"
mkdir -p "$WORK/core-display-framework/Contents/Frameworks/CoreDisplay.framework/Versions/A"
make_macho \
    "$WORK/core-display-framework/Contents/Frameworks/CoreDisplay.framework/Versions/A/CoreDisplay"
expect_rejected "nested CoreDisplay.framework" run_audit "$WORK/core-display-framework"

# Executable nested code must carry its own sandbox entitlement. Loadable
# frameworks remain exempt, as exercised by the positive framework fixtures.
make_app nested-xpc-sandboxed >/dev/null
write_clean_entitlements "$WORK/nested-xpc-sandboxed"
NESTED_XPC_OK="$WORK/nested-xpc-sandboxed/Contents/XPCServices/ExampleService.xpc"
make_macho "$NESTED_XPC_OK/Contents/MacOS/ExampleService"
write_nested_entitlements "$NESTED_XPC_OK"
write_nested_entitlements "$NESTED_XPC_OK/Contents/MacOS/ExampleService"
expect_pass "sandboxed nested XPC executable" run_audit "$WORK/nested-xpc-sandboxed"

make_app nested-xpc-missing-sandbox >/dev/null
write_clean_entitlements "$WORK/nested-xpc-missing-sandbox"
NESTED_XPC_MISSING="$WORK/nested-xpc-missing-sandbox/Contents/XPCServices/ExampleService.xpc"
make_macho "$NESTED_XPC_MISSING/Contents/MacOS/ExampleService"
write_nested_entitlements "$NESTED_XPC_MISSING" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
write_nested_entitlements "$NESTED_XPC_MISSING/Contents/MacOS/ExampleService" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
expect_rejected "nested XPC executable without app-sandbox" \
    run_audit "$WORK/nested-xpc-missing-sandbox"

make_app nested-xpc-false-sandbox >/dev/null
write_clean_entitlements "$WORK/nested-xpc-false-sandbox"
NESTED_XPC_FALSE="$WORK/nested-xpc-false-sandbox/Contents/XPCServices/ExampleService.xpc"
make_macho "$NESTED_XPC_FALSE/Contents/MacOS/ExampleService"
write_nested_entitlements "$NESTED_XPC_FALSE" \
    '    <key>com.apple.security.app-sandbox</key>
    <false/>'
write_nested_entitlements "$NESTED_XPC_FALSE/Contents/MacOS/ExampleService" \
    '    <key>com.apple.security.app-sandbox</key>
    <false/>'
expect_rejected "nested XPC executable with app-sandbox=false" \
    run_audit "$WORK/nested-xpc-false-sandbox"

make_app nested-appex-missing-sandbox >/dev/null
write_clean_entitlements "$WORK/nested-appex-missing-sandbox"
NESTED_APPEX="$WORK/nested-appex-missing-sandbox/Contents/PlugIns/Example.appex"
make_macho "$NESTED_APPEX/Contents/MacOS/Example"
write_nested_entitlements "$NESTED_APPEX" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
write_nested_entitlements "$NESTED_APPEX/Contents/MacOS/Example" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
expect_rejected "nested app extension without app-sandbox" \
    run_audit "$WORK/nested-appex-missing-sandbox"

make_app nested-app-missing-sandbox >/dev/null
write_clean_entitlements "$WORK/nested-app-missing-sandbox"
NESTED_APP="$WORK/nested-app-missing-sandbox/Contents/Library/LoginItems/Helper.app"
make_macho "$NESTED_APP/Contents/MacOS/Helper"
write_nested_entitlements "$NESTED_APP" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
write_nested_entitlements "$NESTED_APP/Contents/MacOS/Helper" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
expect_rejected "nested app executable without app-sandbox" \
    run_audit "$WORK/nested-app-missing-sandbox"

make_app bare-helper-missing-sandbox >/dev/null
write_clean_entitlements "$WORK/bare-helper-missing-sandbox"
BARE_HELPER="$WORK/bare-helper-missing-sandbox/Contents/Helpers/BackgroundTask"
make_macho "$BARE_HELPER"
write_nested_entitlements "$BARE_HELPER" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
expect_rejected "bare helper executable without app-sandbox" \
    run_audit "$WORK/bare-helper-missing-sandbox"

# A genuine dylib stays a loadable library even outside a framework.
make_app genuine-dylib-no-sandbox >/dev/null
write_clean_entitlements "$WORK/genuine-dylib-no-sandbox"
make_macho "$WORK/genuine-dylib-no-sandbox/Contents/Frameworks/Genuine.dylib" 6
expect_pass "genuine dylib without sandbox entitlement" \
    run_audit "$WORK/genuine-dylib-no-sandbox"

# The actual Mach-O file type, not the enclosing container or extension,
# decides whether executable code needs its own sandbox entitlement.
make_app framework-hidden-executable >/dev/null
write_clean_entitlements "$WORK/framework-hidden-executable"
FRAMEWORK_EXECUTABLE="$WORK/framework-hidden-executable/Contents/Frameworks/Public.framework/Versions/A/Resources/RunMe"
make_macho "$FRAMEWORK_EXECUTABLE"
write_nested_entitlements "$FRAMEWORK_EXECUTABLE" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
expect_rejected "MH_EXECUTE hidden inside a framework" \
    run_audit "$WORK/framework-hidden-executable"

make_app disguised-dylib-executable >/dev/null
write_clean_entitlements "$WORK/disguised-dylib-executable"
DISGUISED_EXECUTABLE="$WORK/disguised-dylib-executable/Contents/Helpers/RunMe.dylib"
make_macho "$DISGUISED_EXECUTABLE"
write_nested_entitlements "$DISGUISED_EXECUTABLE" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
expect_rejected "MH_EXECUTE disguised with a dylib extension" \
    run_audit "$WORK/disguised-dylib-executable"

make_app universal-executable-slice >/dev/null
write_clean_entitlements "$WORK/universal-executable-slice"
UNIVERSAL_EXECUTABLE="$WORK/universal-executable-slice/Contents/Frameworks/Mixed.dylib"
make_universal_macho "$UNIVERSAL_EXECUTABLE" 6 2
write_nested_entitlements "$UNIVERSAL_EXECUTABLE" \
    '    <key>com.apple.security.network.client</key>
    <true/>'
expect_rejected "universal Mach-O containing an MH_EXECUTE slice" \
    run_audit "$WORK/universal-executable-slice"

make_app truncated-thin-header >/dev/null
write_clean_entitlements "$WORK/truncated-thin-header"
mkdir -p "$WORK/truncated-thin-header/Contents/Helpers"
printf '\317\372\355\376\007\000\000\001' \
    > "$WORK/truncated-thin-header/Contents/Helpers/Truncated"
expect_rejected "truncated thin Mach-O header" \
    run_audit "$WORK/truncated-thin-header"

make_universal_macho "$WORK/malformed-universal-source" 6 2
make_app truncated-universal-slice >/dev/null
write_clean_entitlements "$WORK/truncated-universal-slice"
mkdir -p "$WORK/truncated-universal-slice/Contents/Helpers"
/usr/bin/head -c 80 "$WORK/malformed-universal-source" \
    > "$WORK/truncated-universal-slice/Contents/Helpers/TruncatedSlice"
expect_rejected "truncated universal Mach-O slice" \
    run_audit "$WORK/truncated-universal-slice"

make_app macho-classification-tool-failure >/dev/null
write_clean_entitlements "$WORK/macho-classification-tool-failure"
make_macho "$WORK/macho-classification-tool-failure/Contents/Frameworks/Genuine.dylib" 6
expect_rejected "Mach-O classification file tool failure" \
    env MOCK_FILE_FAIL=1 PATH="$SHIMS:$PATH" bash "$VERIFIER" \
    "$WORK/macho-classification-tool-failure"

make_app nested-unsigned >/dev/null
write_clean_entitlements "$WORK/nested-unsigned"
NESTED_UNSIGNED="$WORK/nested-unsigned/Contents/Frameworks/Public.framework"
write_nested_entitlements "$NESTED_UNSIGNED"
printf 'unsigned\n' > "$NESTED_UNSIGNED.fixture-verify-fail"
expect_rejected "nested framework signature failure" run_audit "$WORK/nested-unsigned"

make_app nested-get-task-allow >/dev/null
write_clean_entitlements "$WORK/nested-get-task-allow"
NESTED_DEBUG="$WORK/nested-get-task-allow/Contents/Frameworks/Public.framework"
write_nested_entitlements "$NESTED_DEBUG" \
    '    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.get-task-allow</key>
    <true/>'
expect_rejected "nested get-task-allow=true" run_audit "$WORK/nested-get-task-allow"

make_app nested-temporary-exception >/dev/null
write_clean_entitlements "$WORK/nested-temporary-exception"
NESTED_TEMP="$WORK/nested-temporary-exception/Contents/Frameworks/Public.framework"
write_nested_entitlements "$NESTED_TEMP" \
    '    <key>com.apple.security.temporary-exception.files.absolute-path.read-only</key>
    <true/>'
expect_rejected "nested temporary sandbox exception" \
    run_audit "$WORK/nested-temporary-exception"

make_app nested-debugger-entitlement >/dev/null
write_clean_entitlements "$WORK/nested-debugger-entitlement"
NESTED_DEBUGGER="$WORK/nested-debugger-entitlement/Contents/Frameworks/Public.framework"
write_nested_entitlements "$NESTED_DEBUGGER" \
    '    <key>com.apple.security.cs.debugger</key>
    <true/>'
expect_rejected "nested debugger entitlement" \
    run_audit "$WORK/nested-debugger-entitlement"

make_app nested-library-validation >/dev/null
write_clean_entitlements "$WORK/nested-library-validation"
NESTED_LIBRARY="$WORK/nested-library-validation/Contents/Frameworks/Public.framework"
write_nested_entitlements "$NESTED_LIBRARY" \
    '    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>'
expect_rejected "nested library-validation escape entitlement" \
    run_audit "$WORK/nested-library-validation"

# 35-40. Missing, unreadable, non-Mach-O, and escaping content fail closed.
make_app missing-main >/dev/null
write_clean_entitlements "$WORK/missing-main"
unlink "$WORK/missing-main/Contents/MacOS/StatusTrio"
expect_rejected "missing main executable" run_audit "$WORK/missing-main"

make_app non-macho-main >/dev/null
write_clean_entitlements "$WORK/non-macho-main"
printf '#!/bin/sh\nexit 0\n' > "$WORK/non-macho-main/Contents/MacOS/StatusTrio"
chmod +x "$WORK/non-macho-main/Contents/MacOS/StatusTrio"
expect_rejected "non-Mach-O main executable" run_audit "$WORK/non-macho-main"

make_app unreadable-main >/dev/null
write_clean_entitlements "$WORK/unreadable-main"
chmod 000 "$WORK/unreadable-main/Contents/MacOS/StatusTrio"
expect_rejected "unreadable main executable" run_audit "$WORK/unreadable-main"

make_app unreadable-nested >/dev/null
write_clean_entitlements "$WORK/unreadable-nested"
printf 'unreadable\n' > "$WORK/unreadable-nested/Contents/Resources/secret.bin"
chmod 000 "$WORK/unreadable-nested/Contents/Resources/secret.bin"
expect_rejected "unreadable nested file" run_audit "$WORK/unreadable-nested"

make_app unreadable-directory >/dev/null
write_clean_entitlements "$WORK/unreadable-directory"
mkdir -p "$WORK/unreadable-directory/Contents/Resources/Unreadable"
chmod 000 "$WORK/unreadable-directory/Contents/Resources/Unreadable"
expect_rejected "unreadable nested directory" run_audit "$WORK/unreadable-directory"
chmod 700 "$WORK/unreadable-directory/Contents/Resources/Unreadable"

make_app symlink-escape >/dev/null
write_clean_entitlements "$WORK/symlink-escape"
printf 'outside\n' > "$WORK/outside-secret.txt"
ln -s "$WORK/outside-secret.txt" "$WORK/symlink-escape/Contents/Resources/escape.txt"
expect_rejected "symlink escaping the bundle" run_audit "$WORK/symlink-escape"

# 41-46. Every required external tool fails closed.
make_app file-tool-failure >/dev/null
write_clean_entitlements "$WORK/file-tool-failure"
expect_rejected "file tool failure" \
    env MOCK_FILE_FAIL=1 PATH="$SHIMS:$PATH" bash "$VERIFIER" "$WORK/file-tool-failure"

make_app otool-failure >/dev/null
write_clean_entitlements "$WORK/otool-failure"
expect_rejected "otool failure" \
    env MOCK_OTOOL_FAIL=1 PATH="$SHIMS:$PATH" bash "$VERIFIER" "$WORK/otool-failure"

make_app nm-failure >/dev/null
write_clean_entitlements "$WORK/nm-failure"
expect_rejected "nm failure" \
    env MOCK_NM_FAIL=1 PATH="$SHIMS:$PATH" bash "$VERIFIER" "$WORK/nm-failure"

make_app nm-global-empty-failure >/dev/null
write_clean_entitlements "$WORK/nm-global-empty-failure"
expect_rejected "nm global symbol failure with empty output" \
    env MOCK_NM_GLOBAL_EMPTY_FAIL=1 PATH="$SHIMS:$PATH" \
    bash "$VERIFIER" "$WORK/nm-global-empty-failure"

make_app signature-failure >/dev/null
write_clean_entitlements "$WORK/signature-failure"
printf 'fail\n' \
    > "$WORK/signature-failure/Contents/MacOS/StatusTrio.fixture-verify-fail"
expect_rejected "codesign verification failure" run_audit "$WORK/signature-failure"

make_app entitlement-read-failure >/dev/null
printf 'fail\n' \
    > "$WORK/entitlement-read-failure/Contents/MacOS/StatusTrio.fixture-entitlements-fail"
expect_rejected "codesign entitlement read failure" run_audit "$WORK/entitlement-read-failure"

[[ "$SCENARIOS" == "$SCENARIOS_PASSED" ]] ||
    fail "$SCENARIOS_PASSED of $SCENARIOS scenarios passed"

echo "App Store bundle contract passed: $SCENARIOS scenarios"

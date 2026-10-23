#!/usr/bin/env bash
set -euo pipefail

ROOT="${STATUS_TRIO_DEPLOYMENT_CONTRACT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

fail() {
    echo "macOS 13 deployment contract failed: $*" >&2
    exit 1
}

require_file_text() {
    local file="$1"
    local expected="$2"
    grep -Fq -- "$expected" "$file" || fail "$file does not contain: $expected"
}

require_exact() {
    local label="$1"
    local actual="$2"
    local expected="$3"
    [[ "$actual" == "$expected" ]] || fail "$label is '$actual', expected '$expected'"
}

require_exact "Package.swift platform" \
    "$(grep -F 'platforms: [.macOS' Package.swift)" \
    "    platforms: [.macOS(.v13)],"
require_exact "Info.plist LSMinimumSystemVersion" \
    "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Support/Info.plist)" \
    "13.0"
require_exact "release.json minimum" \
    "$(python3 -c 'import json; print(json.load(open("release.json"))["min_system_version"])')" \
    "13.0"
require_exact "mobile battery manifest minimum" \
    "$(python3 -c 'import json; print(json.load(open("Support/mobile-battery-dependencies.json"))["minimumMacOS"])')" \
    "13.0"
require_exact "helper build minimum" \
    "$(sed -n 's/^MINIMUM_MACOS=\"\([^\"]*\)\"$/\1/p' scripts/build-mobile-battery-helper.sh)" \
    "13.0"
require_exact "bundle verifier minimum" \
    "$(sed -n 's/^EXPECTED_MINOS=\"\([^\"]*\)\"$/\1/p' scripts/verify-mobile-battery-bundle.sh)" \
    "13.0"
require_exact "privileged helper verifier minimum" \
    "$(sed -n 's/^EXPECTED_MINOS=\"\([^\"]*\)\"$/\1/p' scripts/verify-privileged-helper-bundle.sh)" \
    "13.0"
require_exact "appcast notes default minimum" \
    "$(sed -n 's/^MINIMUM_SYSTEM_VERSION=\"\${MINIMUM_SYSTEM_VERSION:-\([^\"]*\)}\"$/\1/p' scripts/validate-appcast-notes.sh)" \
    "13.0"
require_exact "appcast generator default minimum" \
    "$(sed -n 's/.*options\[:minimum\] ||= "\([^"]*\)".*/\1/p' scripts/update-appcast.rb)" \
    "13.0"

require_file_text scripts/build-app.sh 'if [[ "${SDK_VERSION%%.*}" -lt 26 ]]; then'
require_file_text scripts/verify-platform-version.sh 'requires SDK ${MINIMUM_SDK_MAJOR} or newer'
require_file_text scripts/build-app.sh 'xcrun vtool -set-build-version macos "$HELPER_MINOS" "$SDK_VERSION"'
require_file_text scripts/build-app.sh 'xcrun vtool -set-build-version macos "$BUILT_MINOS" "$SDK_VERSION"'
if grep -Eq 'xcrun vtool -set-build-version macos "[^"]+" 26\.0' scripts/build-app.sh; then
    fail "build-app.sh hardcodes the design-language SDK instead of the build SDK"
fi

DEPLOYMENT_PATTERN='options\[:minimum\] \|\|= "15\.0"|MINIMUM_MACOS="15\.0"|EXPECTED_MINOS="15\.0"|"min_system_version": "15\.0"|"minimumMacOS": "15\.0"|platforms: \[\.macOS\(\.v15\)\]'
SCANNER_SELECTOR="${STATUS_TRIO_DEPLOYMENT_SCANNER:-auto}"
SCAN_COMMAND=()

case "$SCANNER_SELECTOR" in
auto)
    if command -v rg >/dev/null 2>&1; then
        SCAN_COMMAND=(rg -n --glob '!test-macos13-deployment-contract-regressions.sh')
    elif command -v grep >/dev/null 2>&1; then
        SCAN_COMMAND=(grep -E -R -n --exclude='test-macos13-deployment-contract-regressions.sh')
    else
        fail "no supported scanner is available (rg or grep)"
    fi
    ;;
rg)
    SCANNER="$(command -v rg || true)"
    [[ -n "$SCANNER" ]] || fail "requested scanner rg is not available"
    SCAN_COMMAND=("$SCANNER" -n --glob '!test-macos13-deployment-contract-regressions.sh')
    ;;
grep)
    SCANNER="$(command -v grep || true)"
    [[ -n "$SCANNER" ]] || fail "requested scanner grep is not available"
    SCAN_COMMAND=("$SCANNER" -E -R -n --exclude='test-macos13-deployment-contract-regressions.sh')
    ;;
*)
    SCANNER="$(command -v "$SCANNER_SELECTOR" || true)"
    [[ -n "$SCANNER" ]] || fail "requested scanner '$SCANNER_SELECTOR' is not available"
    SCAN_COMMAND=("$SCANNER" -n)
    ;;
esac

set +e
"${SCAN_COMMAND[@]}" "$DEPLOYMENT_PATTERN" Package.swift Support release.json scripts >/dev/null
SCAN_STATUS=$?
set -e

case "$SCAN_STATUS" in
0)
    fail "a known deployment constant still targets 15.0"
    ;;
1)
    ;;
*)
    fail "deployment constant scan failed with exit status $SCAN_STATUS"
    ;;
esac

echo "macOS 13 deployment contract passed"

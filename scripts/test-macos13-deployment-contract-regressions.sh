#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACT="$ROOT/scripts/test-macos13-deployment-contract.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioDeploymentContract.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "deployment contract regression failed: $*" >&2
    exit 1
}

make_fixture() {
    local fixture="$1"
    mkdir -p "$fixture/Support" "$fixture/scripts"

    cat > "$fixture/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fixture",
    platforms: [.macOS(.v13)],
    products: []
)
SWIFT

    cat > "$fixture/Support/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST

    printf '{"min_system_version": "13.0"}\n' > "$fixture/release.json"
    printf '{"minimumMacOS": "13.0"}\n' > "$fixture/Support/mobile-battery-dependencies.json"

    cat > "$fixture/scripts/build-mobile-battery-helper.sh" <<'SH'
MINIMUM_MACOS="13.0"
SH
    cat > "$fixture/scripts/verify-mobile-battery-bundle.sh" <<'SH'
EXPECTED_MINOS="13.0"
SH
    cat > "$fixture/scripts/verify-privileged-helper-bundle.sh" <<'SH'
EXPECTED_MINOS="13.0"
SH
    cat > "$fixture/scripts/validate-appcast-notes.sh" <<'SH'
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-13.0}"
SH
    cat > "$fixture/scripts/update-appcast.rb" <<'RUBY'
options[:minimum] ||= "13.0"
RUBY
    cat > "$fixture/scripts/build-app.sh" <<'SH'
if [[ "${SDK_VERSION%%.*}" -lt 26 ]]; then
    exit 1
fi
SH
    cat > "$fixture/scripts/verify-platform-version.sh" <<'SH'
echo 'requires SDK ${MINIMUM_SDK_MAJOR} or newer'
SH
}

make_fallback_path() {
    local fallback_path="$1"
    mkdir -p "$fallback_path"

    local tool
    for tool in bash dirname grep python3 sed; do
        ln -s "$(command -v "$tool")" "$fallback_path/$tool"
    done

    if PATH="$fallback_path" "$fallback_path/bash" -c 'command -v /usr/libexec/PlistBuddy >/dev/null 2>&1'; then
        mkdir -p "$fallback_path/usr/libexec"
        ln -s /usr/libexec/PlistBuddy "$fallback_path/usr/libexec/PlistBuddy"
    fi

    if PATH="$fallback_path" command -v rg >/dev/null 2>&1; then
        fail "the automatic fallback fixture unexpectedly exposes rg"
    fi
}

run_contract() {
    local fixture="$1"
    shift
    STATUS_TRIO_DEPLOYMENT_CONTRACT_ROOT="$fixture" "$@" bash "$CONTRACT" >/dev/null 2>&1
}

expect_success() {
    local label="$1"
    shift
    if ! "$@"; then
        fail "$label was rejected"
    fi
}

expect_failure() {
    local label="$1"
    shift
    if "$@"; then
        fail "$label was accepted"
    fi
}

valid="$WORK/valid"
make_fixture "$valid"
expect_success "valid macOS 13 fixture" run_contract "$valid"
expect_success "valid fixture with the grep fallback" \
    run_contract "$valid" env STATUS_TRIO_DEPLOYMENT_SCANNER="grep"

forbidden="$WORK/forbidden"
make_fixture "$forbidden"
cat > "$forbidden/scripts/forbidden-fixture.sh" <<'SH'
MINIMUM_MACOS="15.0"
SH
expect_failure "forbidden 15.0 fixture" run_contract "$forbidden"

fallback_path="$WORK/fallback-path"
make_fallback_path "$fallback_path"
expect_success "valid fixture with the automatic grep fallback" \
    run_contract "$valid" env PATH="$fallback_path"
expect_failure "forbidden 15.0 fixture with the automatic grep fallback" \
    run_contract "$forbidden" env PATH="$fallback_path"

missing_scanner="$WORK/missing-scanner"
make_fixture "$missing_scanner"
expect_failure "missing scanner" \
    run_contract "$missing_scanner" env STATUS_TRIO_DEPLOYMENT_SCANNER="status-trio-missing-scanner"

scanner_failure="$WORK/scanner-failure"
make_fixture "$scanner_failure"
cat > "$scanner_failure/failing-scanner" <<'SH'
#!/usr/bin/env bash
exit 2
SH
chmod +x "$scanner_failure/failing-scanner"
expect_failure "scanner execution error" \
    run_contract "$scanner_failure" env STATUS_TRIO_DEPLOYMENT_SCANNER="$scanner_failure/failing-scanner"

echo "macOS 13 deployment contract regressions passed"

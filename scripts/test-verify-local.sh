#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioVerifyLocal.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "verify-local contract failed: $*" >&2
    exit 1
}

expect_failure() {
    local label="$1"
    shift
    if "$@" >"$WORK/output.log" 2>&1; then
        fail "$label was accepted"
    fi
}

make_fixture() {
    local fixture="$1"
    mkdir -p "$fixture/scripts"
    cp "$ROOT/scripts/verify-local.sh" "$fixture/scripts/verify-local.sh"
    cp "$ROOT/scripts/test.sh" "$fixture/scripts/test.sh"
    chmod +x "$fixture/scripts/verify-local.sh" "$fixture/scripts/test.sh"

    cat > "$fixture/scripts/check-forbidden-patterns.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'forbidden\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-macos13-deployment-contract.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'deployment\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-macos13-deployment-contract-regressions.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'deployment-regressions\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-appcast-minimum-system-version.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'appcast\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-privileged-helper-bundle-contract.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'helper-contract\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-mobile-battery-helper.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'mobile-helper\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-mobile-battery-rpaths.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'mobile-rpaths\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-otool-dependencies.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'otool\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-macos13-sparkle-contract.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'sparkle\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-mobile-battery-source-cache.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'mobile-source-cache\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-release-workflow-policy.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'release-policy\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-release-pipeline.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'release-pipeline\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-release-notarization.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'release-notarization\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-mobile-battery-clang-version.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'clang\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-verify-local.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'self-test\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-workflow-policy.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'workflow-policy\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-macos13-bundle-contract.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'bundle\n' >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/test-verify-local-bundle.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'bundle-self-test\n' >> "${VERIFY_TRACE:?}"
SH
    local store_check
    for store_check in app-store-project-contract app-store-source-closure app-store-bundle-contract app-store-archive-dsyms dual-distribution-workflows; do
        cat > "$fixture/scripts/test-$store_check.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(basename "$0" .sh)" >> "${VERIFY_TRACE:?}"
exit "${STORE_CHECK_STATUS:-0}"
SH
    done
    cat > "$fixture/scripts/build-app.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'build-app %s BUNDLE_ID=%s APP_NAME=%s UNIVERSAL_BUILD=%s\n' \
    "$*" "${BUNDLE_ID:-}" "${APP_NAME:-}" "${UNIVERSAL_BUILD:-}" >> "${VERIFY_TRACE:?}"
if [[ "${BUILD_APP_STATUS:-0}" != "0" ]]; then
    printf 'error: deterministic app bundle failure\n' >&2
    exit "$BUILD_APP_STATUS"
fi
SH
    cat > "$fixture/scripts/verify-platform-version.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'platform %s\n' "$*" >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/verify-mobile-battery-bundle.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'mobile-bundle %s\n' "$*" >> "${VERIFY_TRACE:?}"
SH
    cat > "$fixture/scripts/verify-privileged-helper-bundle.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'helper-bundle %s\n' "$*" >> "${VERIFY_TRACE:?}"
SH

    cat > "$fixture/swift" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'swift %s\n' "$*" >> "${VERIFY_TRACE:?}"
if [[ "$1" == "test" ]]; then
    if [[ "$*" == "test --filter NoMatchGuardTests" ]]; then
        printf 'warning: No matching test cases were run\n' >&2
        exit 0
    fi
    if [[ -n "${SWIFT_TEST_STDERR:-}" ]]; then
        printf '%s\n' "$SWIFT_TEST_STDERR" >&2
    fi
    exit "${SWIFT_TEST_STATUS:-0}"
fi
if [[ "$1" == "build" ]]; then
    exit "${SWIFT_BUILD_STATUS:-0}"
fi
if [[ "$1" == "--version" ]]; then
    printf 'Swift fixture\n'
    exit 0
fi
exit 2
SH
    chmod +x "$fixture/swift"

    cat > "$fixture/xcodebuild" <<'SH'
#!/usr/bin/env bash
printf 'Xcode fixture\n'
SH
    cat > "$fixture/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "rev-parse --verify HEAD" ]]; then
    printf '0123456789abcdef0123456789abcdef01234567\n'
    exit 0
fi
if [[ "$*" == "status --porcelain=v1 --untracked-files=all" ]]; then
    printf '%s' "${GIT_STATUS:-}"
    exit 0
fi
if [[ "$*" == "branch --show-current" ]]; then
    printf 'codex/fixture\n'
    exit 0
fi
exec /usr/bin/git "$@"
SH
    cat > "$fixture/xcrun" <<'SH'
#!/usr/bin/env bash
printf '27.0\n'
SH
    chmod +x "$fixture/xcodebuild" "$fixture/git" "$fixture/xcrun" \
        "$fixture/scripts/build-app.sh" \
        "$fixture/scripts/verify-platform-version.sh" \
        "$fixture/scripts/verify-mobile-battery-bundle.sh" \
        "$fixture/scripts/verify-privileged-helper-bundle.sh" \
        "$fixture/scripts/test-verify-local-bundle.sh"
}

make_fixture "$WORK/repo"
export PATH="$WORK/repo:$PATH"
export VERIFY_TRACE="$WORK/trace"

expect_failure "missing verification mode" bash "$WORK/repo/scripts/verify-local.sh"
expect_failure "unknown verification mode" bash "$WORK/repo/scripts/verify-local.sh" "release"
expect_failure "unknown two-word verification mode" bash "$WORK/repo/scripts/verify-local.sh" "quick check"
if [[ -e "$VERIFY_TRACE" ]]; then
    fail "argument validation ran a verification step"
fi

bash "$WORK/repo/scripts/verify-local.sh" quick >"$WORK/quick.log" 2>&1 ||
    fail "quick verification failed"
for expected in forbidden "swift test --filter"; do
    grep -Fq "$expected" "$VERIFY_TRACE" ||
        fail "quick verification did not run $expected"
done
grep -Fq "0123456789abcdef0123456789abcdef01234567" "$WORK/quick.log" ||
    fail "quick verification did not report HEAD"
grep -Fq "Xcode fixture" "$WORK/quick.log" ||
    fail "quick verification did not report Xcode"
grep -Fq "quick" "$WORK/quick.log" ||
    fail "quick verification did not report its scope"
if grep -Fq "deployment" "$VERIFY_TRACE"; then
    fail "quick verification ran full compatibility checks"
fi
if [[ -s "$WORK/repo/.build/local-verification/status.txt" ]]; then
    fail "successful quick verification wrote a failure record"
fi

: > "$VERIFY_TRACE"
bash "$WORK/repo/scripts/verify-local.sh" quick BatteryMonitorTests >"$WORK/filtered.log" 2>&1 ||
    fail "filtered quick verification failed"
grep -Fq "swift test --filter BatteryMonitorTests" "$VERIFY_TRACE" ||
    fail "quick verification did not pass a focused filter to test.sh"

: > "$VERIFY_TRACE"
expect_failure "a focused filter that matches no tests" \
    bash "$WORK/repo/scripts/verify-local.sh" quick NoMatchGuardTests
grep -Fq "step=Forbidden patterns + focused tests" \
    "$WORK/repo/.build/local-verification/status.txt" ||
    fail "zero-match verification did not record the focused-test step"
grep -Fq "Swift test filter matched no test cases" \
    "$WORK/repo/.build/local-verification/log.txt" ||
    fail "zero-match verification did not fail with the filter guard message"

: > "$VERIFY_TRACE"
SWIFT_TEST_STDERR="error: deterministic fixture failure" SWIFT_TEST_STATUS=7 \
    expect_failure "a failing quick verification" \
    bash "$WORK/repo/scripts/verify-local.sh" quick BatteryMonitorTests
grep -Fq "quick" "$WORK/repo/.build/local-verification/status.txt" ||
    fail "failed quick verification did not record its mode"
grep -Fq "Forbidden patterns" "$WORK/repo/.build/local-verification/status.txt" ||
    fail "failed quick verification did not record the failed step"
grep -Fq "error: deterministic fixture failure" "$WORK/repo/.build/local-verification/log.txt" ||
    fail "failed quick verification did not preserve the failure log"

: > "$VERIFY_TRACE"
GIT_STATUS=" M Sources/StatusTrio/StatusTrioApp.swift" \
    bash "$WORK/repo/scripts/verify-local.sh" quick >"$WORK/dirty.log" 2>&1 ||
    fail "quick verification rejected an uncommitted allowed file"
grep -Fq "uncommitted: 1 change" "$WORK/dirty.log" ||
    fail "quick verification did not report its uncommitted change"

: > "$VERIFY_TRACE"
GIT_STATUS=$'?? Tests/StatusTrioCoreTests/NewRegressionTests.swift\n' \
    bash "$WORK/repo/scripts/verify-local.sh" quick >"$WORK/untracked.log" 2>&1 ||
    fail "quick verification rejected an untracked source or test file"
grep -Fq "uncommitted: 1 change" "$WORK/untracked.log" ||
    fail "quick verification did not report an untracked change"
if grep -Fq "untracked files ignored" "$WORK/untracked.log"; then
    fail "quick verification claimed untracked files were ignored"
fi

: > "$VERIFY_TRACE"
bash "$WORK/repo/scripts/verify-local.sh" docs >"$WORK/docs.log" 2>&1 ||
    fail "documentation/localization verification failed"
for expected in forbidden "swift test --filter LocalizationTests" \
    "swift test --filter LocalizationParityTests" \
    "swift test --filter ChargingEffectLocalizationTests" \
    "swift test --filter MenuBarHelpLocalizationTests" \
    "workflow-policy" "test-dual-distribution-workflows"; do
    grep -Fq "$expected" "$VERIFY_TRACE" ||
        fail "docs verification did not run $expected"
done
if grep -Fq "BatteryMonitorTests" "$VERIFY_TRACE" ||
    grep -Fq "deployment" "$VERIFY_TRACE" ||
    grep -Fq "build-app" "$VERIFY_TRACE"; then
    fail "docs verification ran a quick or full test/build scope"
fi
grep -Fq "mode: docs" "$WORK/docs.log" ||
    fail "docs verification did not report its mode"

: > "$VERIFY_TRACE"
bash "$WORK/repo/scripts/verify-local.sh" full >"$WORK/full.log" 2>&1 ||
    fail "full verification failed"
for expected in forbidden "swift test" "swift build -c release" deployment deployment-regressions \
    appcast helper-contract mobile-helper mobile-rpaths otool sparkle mobile-source-cache release-policy \
    release-pipeline release-notarization clang self-test \
    workflow-policy bundle-self-test bundle \
    test-app-store-project-contract test-app-store-source-closure \
    test-app-store-bundle-contract test-app-store-archive-dsyms test-dual-distribution-workflows \
    "build-app release no-open" \
    "BUNDLE_ID=com.lingsmbp.StatusTrio.dev.verify-local" \
    "APP_NAME=Status Trio (Verify Local)" "UNIVERSAL_BUILD=0" \
    "platform dist/StatusTrio.app/Contents/MacOS/StatusTrio 13.0 26" \
    "mobile-bundle dist/StatusTrio.app" "helper-bundle dist/StatusTrio.app"; do
    grep -Fq "$expected" "$VERIFY_TRACE" ||
        fail "full verification did not run $expected"
done
if [[ -s "$WORK/repo/.build/local-verification/status.txt" ]]; then
    fail "successful full verification wrote a failure record"
fi
grep -Fq "full" "$WORK/full.log" ||
    fail "full verification did not report its scope"
grep -Fq "non-Universal" "$WORK/full.log" ||
    fail "full verification did not disclose its non-Universal bundle boundary"

rm -rf "$WORK/repo/.build/local-verification"
: > "$VERIFY_TRACE"
BUILD_APP_STATUS=11 expect_failure "a failing full app bundle build" \
    bash "$WORK/repo/scripts/verify-local.sh" full
grep -Fq "App bundle build" "$WORK/repo/.build/local-verification/status.txt" ||
    fail "failed full verification did not record the app bundle step"
grep -Fq "error: deterministic app bundle failure" "$WORK/repo/.build/local-verification/log.txt" ||
    fail "failed app bundle build did not preserve its failure log"
if grep -Fq "mobile-bundle" "$VERIFY_TRACE"; then
    fail "full verification continued into bundle checks after the app build failed"
fi

rm -rf "$WORK/repo/.build/local-verification"
: > "$VERIFY_TRACE"
SWIFT_BUILD_STATUS=9 expect_failure "a failing full build" \
    bash "$WORK/repo/scripts/verify-local.sh" full
grep -Fq "Release build" "$WORK/repo/.build/local-verification/status.txt" ||
    fail "failed full verification did not record the Release build step"

rm -rf "$WORK/repo/.build/local-verification"
: > "$VERIFY_TRACE"
STORE_CHECK_STATUS=12 expect_failure "a failing Store contract" \
    bash "$WORK/repo/scripts/verify-local.sh" full
grep -Fq "test-app-store-project-contract.sh" "$WORK/repo/.build/local-verification/status.txt" ||
    fail "failed full verification did not record the Store contract step"
grep -Fq "exit=12" "$WORK/repo/.build/local-verification/status.txt" ||
    fail "failed Store contract exit status was lost"
if grep -Fq "test-app-store-source-closure" "$VERIFY_TRACE"; then
    fail "full verification continued after the Store contract failed"
fi

echo "verify-local contract passed"

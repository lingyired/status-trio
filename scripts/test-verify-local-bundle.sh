#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/StatusTrioVerifyLocalBundle.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "verify-local bundle contract failed: $*" >&2
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
    mkdir -p "$fixture/scripts" "$fixture/dist/StatusTrio.app/Contents/MacOS"
    cp "$ROOT/scripts/verify-local.sh" "$fixture/scripts/verify-local.sh"
    chmod +x "$fixture/scripts/verify-local.sh"

    cat > "$fixture/swift" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'swift %s\n' "$*" >> "${VERIFY_BUNDLE_TRACE:?}"
case "$1" in
    test|build) exit 0 ;;
    --version) printf 'Swift fixture\n'; exit 0 ;;
esac
exit 2
SH
    cat > "$fixture/xcodebuild" <<'SH'
#!/usr/bin/env bash
printf 'Xcode fixture\n'
SH
    cat > "$fixture/xcrun" <<'SH'
#!/usr/bin/env bash
printf '27.0\n'
SH
    cat > "$fixture/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
    "rev-parse --verify HEAD") printf '0123456789abcdef0123456789abcdef01234567\n' ;;
    "status --porcelain=v1 --untracked-files=all") printf '' ;;
    "branch --show-current") printf 'codex/fixture\n' ;;
    *) exec /usr/bin/git "$@" ;;
esac
SH
    chmod +x "$fixture/swift" "$fixture/xcodebuild" "$fixture/xcrun" "$fixture/git"

    local script
    for script in test.sh test-workflow-policy.sh test-macos13-deployment-contract-regressions.sh \
        test-macos13-deployment-contract.sh test-appcast-minimum-system-version.sh \
        test-macos13-bundle-contract.sh test-privileged-helper-bundle-contract.sh \
        test-mobile-battery-helper.sh test-mobile-battery-rpaths.sh test-otool-dependencies.sh \
        test-macos13-sparkle-contract.sh test-mobile-battery-source-cache.sh \
        test-mobile-battery-clang-version.sh test-release-workflow-policy.sh \
        test-release-pipeline.sh test-release-notarization.sh \
        test-app-store-project-contract.sh test-app-store-source-closure.sh \
        test-app-store-bundle-contract.sh test-app-store-archive-dsyms.sh \
        test-dual-distribution-workflows.sh \
        test-verify-local.sh test-verify-local-bundle.sh; do
        cat > "$fixture/scripts/$script" <<SH
#!/usr/bin/env bash
set -euo pipefail
printf '$script\n' >> "\${VERIFY_BUNDLE_TRACE:?}"
SH
        chmod +x "$fixture/scripts/$script"
    done

    cat > "$fixture/scripts/build-app.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'build-app %s %s %s %s\n' "$*" "${BUNDLE_ID:-}" "${APP_NAME:-}" "${UNIVERSAL_BUILD:-}" >> "${VERIFY_BUNDLE_TRACE:?}"
mkdir -p "$PWD/dist/StatusTrio.app/Contents/MacOS"
printf '#!/bin/sh\nexit 0\n' > "$PWD/dist/StatusTrio.app/Contents/MacOS/StatusTrio"
chmod +x "$PWD/dist/StatusTrio.app/Contents/MacOS/StatusTrio"
SH
    cat > "$fixture/scripts/verify-platform-version.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ -f "$1" ]] || { echo "missing built binary: $1" >&2; exit 1; }
printf 'platform %s\n' "$*" >> "${VERIFY_BUNDLE_TRACE:?}"
SH
    cat > "$fixture/scripts/verify-mobile-battery-bundle.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ -d "$1" ]] || { echo "missing app bundle: $1" >&2; exit 1; }
printf 'mobile-bundle %s\n' "$*" >> "${VERIFY_BUNDLE_TRACE:?}"
SH
    cat > "$fixture/scripts/verify-privileged-helper-bundle.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ -d "$1" ]] || { echo "missing app bundle: $1" >&2; exit 1; }
printf 'helper-bundle %s\n' "$*" >> "${VERIFY_BUNDLE_TRACE:?}"
SH
    chmod +x "$fixture/scripts/build-app.sh" \
        "$fixture/scripts/verify-platform-version.sh" \
        "$fixture/scripts/verify-mobile-battery-bundle.sh" \
        "$fixture/scripts/verify-privileged-helper-bundle.sh"
}

make_fixture "$WORK/repo"
export PATH="$WORK/repo:$PATH"
export VERIFY_BUNDLE_TRACE="$WORK/trace"

: > "$VERIFY_BUNDLE_TRACE"
if ! bash "$WORK/repo/scripts/verify-local.sh" full >"$WORK/full.log" 2>&1; then
    cat "$WORK/full.log" >&2
    fail "full verification with an app-producing build failed"
fi

for expected in \
    "build-app release no-open com.lingsmbp.StatusTrio.dev.verify-local Status Trio (Verify Local) 0" \
    "platform dist/StatusTrio.app/Contents/MacOS/StatusTrio 13.0 26" \
    "mobile-bundle dist/StatusTrio.app" \
    "helper-bundle dist/StatusTrio.app"; do
    grep -Fq "$expected" "$VERIFY_BUNDLE_TRACE" ||
        fail "full verification did not run $expected"
done

build_line="$(grep -nF "build-app release no-open" "$VERIFY_BUNDLE_TRACE" | cut -d: -f1)"
platform_line="$(grep -nF "platform dist/StatusTrio.app/Contents/MacOS/StatusTrio" "$VERIFY_BUNDLE_TRACE" | cut -d: -f1)"
mobile_line="$(grep -nF "mobile-bundle dist/StatusTrio.app" "$VERIFY_BUNDLE_TRACE" | cut -d: -f1)"
helper_line="$(grep -nF "helper-bundle dist/StatusTrio.app" "$VERIFY_BUNDLE_TRACE" | cut -d: -f1)"
(( build_line < platform_line && platform_line < mobile_line && mobile_line < helper_line )) ||
    fail "app bundle checks did not run in build -> platform -> helpers order"

if [[ -s "$WORK/repo/.build/local-verification/status.txt" ]]; then
    fail "successful bundle verification wrote a failure record"
fi

cat > "$WORK/repo/scripts/verify-mobile-battery-bundle.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'mobile-bundle %s\n' "$*" >> "${VERIFY_BUNDLE_TRACE:?}"
echo "error: deterministic mobile bundle failure" >&2
exit 13
SH
chmod +x "$WORK/repo/scripts/verify-mobile-battery-bundle.sh"
rm -rf "$WORK/repo/.build/local-verification"
: > "$VERIFY_BUNDLE_TRACE"

expect_failure "a failing mobile bundle check" bash "$WORK/repo/scripts/verify-local.sh" full
grep -Fq "step=Mobile battery bundle" "$WORK/repo/.build/local-verification/status.txt" ||
    fail "mobile bundle failure was not recorded at its own step"
grep -Fq "error: deterministic mobile bundle failure" \
    "$WORK/repo/.build/local-verification/log.txt" ||
    fail "mobile bundle failure did not preserve its log"
if grep -Fq "helper-bundle" "$VERIFY_BUNDLE_TRACE"; then
    fail "full verification continued into helper checks after the mobile bundle failed"
fi

echo "verify-local bundle contract passed"

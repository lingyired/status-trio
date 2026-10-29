#!/usr/bin/env bash
# Risk-sized local verification for agent work. This intentionally stops short
# of release packaging, signing, notarization, and publication.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-}"
if [[ "$MODE" != "quick" && "$MODE" != "docs" && "$MODE" != "full" ]]; then
    echo "Usage: $0 <quick|docs|full> [swift-test-filter]" >&2
    exit 2
fi

FILTER="${2:-ForbiddenPatternGuardTests|Issue30WiFiAlignmentTests|IconSurfaceIntegrationTests}"
LOG_DIR="$ROOT/.build/local-verification"
LOG_FILE="$LOG_DIR/log.txt"
STATUS_FILE="$LOG_DIR/status.txt"
mkdir -p "$LOG_DIR"
: > "$LOG_FILE"
: > "$STATUS_FILE"

step_failed() {
    local step="$1"
    local status="$2"
    {
        printf 'mode=%s\n' "$MODE"
        printf 'step=%s\n' "$step"
        printf 'exit=%s\n' "$status"
    } > "$STATUS_FILE"
    echo "Local verification failed: mode=$MODE step=$step exit=$status" >&2
    echo "Log: $LOG_FILE" >&2
    exit "$status"
}

run_step() {
    local label="$1"
    shift
    local status log_file
    log_file="$(mktemp "${TMPDIR:-/tmp}/StatusTrioVerifyStep.XXXXXX")"
    printf '\n== %s ==\n' "$label" | tee -a "$LOG_FILE"
    printf '  $' | tee -a "$LOG_FILE"
    printf ' %q' "$@" | tee -a "$LOG_FILE"
    printf '\n' | tee -a "$LOG_FILE"

    set +e
    "$@" >"$log_file" 2>&1
    status=$?
    set -e
    cat "$log_file" >> "$LOG_FILE"
    cat "$log_file"
    rm -f "$log_file"

    if [[ "$status" -ne 0 ]]; then
        step_failed "$label" "$status"
    fi
}

HEAD="$(git rev-parse --verify HEAD)"
BRANCH="$(git branch --show-current 2>/dev/null || true)"
[[ -n "$BRANCH" ]] || BRANCH="detached"
WORKING_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
WORKING_CHANGES="$(printf '%s\n' "$WORKING_STATUS" | awk 'NF { count++ } END { print count + 0 }')"

echo "Local verification"
echo "mode: $MODE"
echo "head: $HEAD"
echo "branch: $BRANCH"
if [[ "$WORKING_CHANGES" -eq 0 ]]; then
    echo "working tree: clean"
else
    echo "uncommitted: $WORKING_CHANGES change$([[ "$WORKING_CHANGES" -eq 1 ]] || echo s)"
fi
echo "scope: $MODE"
echo "not verified: UI/runtime behavior, hardware, signing, notarization, DMG, release, appcast"
echo "toolchain:"

run_step "Xcode version" xcodebuild -version
run_step "Swift version" swift --version
run_step "macOS SDK version" xcrun --sdk macosx --show-sdk-version

shopt -s nullglob
SYNTAX_FILES=("scripts/"*.sh)
run_step "Shell syntax" bash -n "${SYNTAX_FILES[@]}"

if [[ "$MODE" == "quick" ]]; then
    echo "quick filter: $FILTER"
    run_step "Forbidden patterns + focused tests" bash scripts/test.sh "$FILTER"
elif [[ "$MODE" == "docs" ]]; then
    DOC_TEST_FILTERS=(
        LocalizationTests
        LocalizationParityTests
        ChargingEffectLocalizationTests
        MenuBarHelpLocalizationTests
    )
    for filter in "${DOC_TEST_FILTERS[@]}"; do
        run_step "Documentation: $filter" bash scripts/test.sh "$filter"
    done
    run_step "Documentation policy" bash scripts/test-workflow-policy.sh
    run_step "Dual-distribution workflow policy" bash scripts/test-dual-distribution-workflows.sh
else
    run_step "Swift tests + forbidden patterns" bash scripts/test.sh
    run_step "Release build" swift build -c release
    APP_DIR="$ROOT/dist/StatusTrio.app"
    if [[ -n "$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        echo "Removing stale local app bundle before verification: $APP_DIR"
        rm -rf "$APP_DIR"
    fi
    run_step "App bundle build" env \
        BUNDLE_ID=com.lingsmbp.StatusTrio.dev.verify-local \
        APP_NAME="Status Trio (Verify Local)" \
        UNIVERSAL_BUILD=0 \
        bash scripts/build-app.sh release no-open
    run_step "Platform and SDK contract" bash scripts/verify-platform-version.sh \
        dist/StatusTrio.app/Contents/MacOS/StatusTrio 13.0 26
    run_step "Mobile battery bundle" bash scripts/verify-mobile-battery-bundle.sh dist/StatusTrio.app
    run_step "Privileged helper bundle" bash scripts/verify-privileged-helper-bundle.sh dist/StatusTrio.app

    NATIVE_CHECKS=(
        "scripts/test-macos13-deployment-contract-regressions.sh"
        "scripts/test-macos13-deployment-contract.sh"
        "scripts/test-appcast-minimum-system-version.sh"
        "scripts/test-macos13-bundle-contract.sh"
        "scripts/test-privileged-helper-bundle-contract.sh"
        "scripts/test-mobile-battery-helper.sh"
        "scripts/test-mobile-battery-rpaths.sh"
        "scripts/test-otool-dependencies.sh"
        "scripts/test-macos13-sparkle-contract.sh"
        "scripts/test-mobile-battery-source-cache.sh"
        "scripts/test-release-workflow-policy.sh"
        "scripts/test-release-pipeline.sh"
        "scripts/test-release-notarization.sh"
        "scripts/test-mobile-battery-clang-version.sh"
        "scripts/test-verify-local.sh"
        "scripts/test-verify-local-bundle.sh"
        "scripts/test-workflow-policy.sh"
        "scripts/test-app-store-project-contract.sh"
        "scripts/test-app-store-source-closure.sh"
        "scripts/test-app-store-bundle-contract.sh"
        "scripts/test-app-store-archive-dsyms.sh"
        "scripts/test-dual-distribution-workflows.sh"
    )
    for check in "${NATIVE_CHECKS[@]}"; do
        run_step "Native check: $(basename "$check")" bash "$check"
    done
fi

echo
echo "Local verification passed: mode=$MODE head=$HEAD"
if [[ "$MODE" == "quick" ]]; then
    echo "This is focused local evidence, not a full suite, runtime check, or release approval."
elif [[ "$MODE" == "docs" ]]; then
    echo "This is documentation/localization evidence, not a full suite or runtime check."
else
    echo "Full local checks include a non-Universal ad hoc app bundle and bundle contracts."
    echo "They do not replace signing, notarization, DMG, formal release CI, Universal packaging,"
    echo "or macOS 13/macOS 26+ runtime acceptance."
fi

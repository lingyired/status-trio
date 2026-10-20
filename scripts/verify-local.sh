#!/usr/bin/env bash
# Risk-sized local verification for agent work. This intentionally stops short
# of release packaging, signing, notarization, and publication.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-}"
if [[ "$MODE" != "quick" && "$MODE" != "full" ]]; then
    echo "Usage: $0 <quick|full> [swift-test-filter]" >&2
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
TRACKED_STATUS="$(git status --porcelain=v1 --untracked-files=no)"
TRACKED_CHANGES="$(printf '%s\n' "$TRACKED_STATUS" | awk 'NF { count++ } END { print count + 0 }')"

echo "Local verification"
echo "mode: $MODE"
echo "head: $HEAD"
echo "branch: $BRANCH"
if [[ "$TRACKED_CHANGES" -eq 0 ]]; then
    echo "working tree: no tracked changes; untracked files ignored"
else
    echo "uncommitted: $TRACKED_CHANGES tracked change$([[ "$TRACKED_CHANGES" -eq 1 ]] || echo s)"
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
else
    run_step "Swift tests + forbidden patterns" bash scripts/test.sh
    run_step "Release build" swift build -c release

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
        "scripts/test-mobile-battery-clang-version.sh"
        "scripts/test-verify-local.sh"
        "scripts/test-workflow-policy.sh"
    )
    for check in "${NATIVE_CHECKS[@]}"; do
        run_step "Native check: $(basename "$check")" bash "$check"
    done
fi

echo
echo "Local verification passed: mode=$MODE head=$HEAD"
if [[ "$MODE" == "quick" ]]; then
    echo "This is focused local evidence, not a full suite, runtime check, or release approval."
else
    echo "Full local checks do not replace the formal release CI or macOS 13/macOS 26+ runtime acceptance."
fi

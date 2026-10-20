#!/usr/bin/env bash
# Fails closed when the local-first policy or its release-only exception drifts.
set -euo pipefail

ROOT="${STATUS_TRIO_POLICY_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

fail() {
    echo "workflow policy check failed: $*" >&2
    exit 1
}

require_text() {
    local path="$1"
    local text="$2"
    grep -Fq -- "$text" "$path" || fail "$path must contain: $text"
}

AGENTS="$ROOT/AGENTS.md"
PR_TEMPLATE="$ROOT/.github/pull_request_template.md"

[[ -f "$AGENTS" ]] || fail "AGENTS.md is missing"
[[ -f "$PR_TEMPLATE" ]] || fail ".github/pull_request_template.md is missing"

for stale in \
    "Before committing Swift changes" \
    "release workflow before merging or publishing" \
    "run a non-publishing release workflow before merging" \
    "GitHub Actions preflight is required" \
    "must be added to" \
    "Every failed GitHub Actions run must be added" \
    "The release workflow is the acceptance environment" \
    "publish=false is required before merge"; do
    if grep -Fq -- "$stale" "$AGENTS"; then
        fail "AGENTS.md still requires per-change remote CI: $stale"
    fi
done

for required in \
    "Local-First Change Flow" \
    "quick" \
    "full" \
    "only before a formal release" \
    "merged" \
    "built" \
    "released" \
    "macOS 13" \
    "macOS 26" \
    "scripts/build-worktree.sh" \
    "scripts/verify-local.sh"; do
    require_text "$AGENTS" "$required"
done

require_text "$AGENTS" 'bash scripts/verify-local.sh <quick|docs|full>'

for rule in rendering bluetooth network macos-compatibility performance release release-validation; do
    require_text "$AGENTS" ".agents/rules/$rule.md"
    [[ -f "$ROOT/.agents/rules/$rule.md" ]] || fail "mapped rule is missing: .agents/rules/$rule.md"
done

for section in "Motivation and scope" "Verification" "Risk and unverified items"; do
    require_text "$PR_TEMPLATE" "## $section"
done
for evidence in "Commands" "Result" "SHA" "Visual" "Performance" "Release" "Issue"; do
    require_text "$PR_TEMPLATE" "$evidence"
done

if grep -Fq "Release CI is not required" "$AGENTS" ||
    grep -Fq "Skip formal release CI" "$AGENTS"; then
    fail "AGENTS.md contains a release verification bypass"
fi

echo "workflow policy check passed"

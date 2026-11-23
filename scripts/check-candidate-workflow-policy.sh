#!/usr/bin/env bash
# Fails closed when the build/publish/verify candidate workflows regress or the
# Publish Existing Candidate workflow gains any build, sign, or notarize power.
set -euo pipefail

ROOT="${STATUS_TRIO_CANDIDATE_POLICY_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
BUILD_WF="$ROOT/.github/workflows/build-candidate.yml"
PUBLISH_WF="$ROOT/.github/workflows/publish-candidate.yml"
VERIFY_WF="$ROOT/.github/workflows/verify-candidate.yml"

fail() { echo "candidate workflow policy check failed: $*" >&2; exit 1; }
require_text() { grep -Fq -- "$2" "$1" || fail "$1 must contain: $2"; }
forbid_text() {
    local path="$1" text="$2"
    [[ -f "$path" && -r "$path" ]] || fail "$path is missing or unreadable"
    if grep -Fq -- "$text" "$path"; then
        fail "$path must not contain: $text"
    fi
}

for workflow in "$BUILD_WF" "$PUBLISH_WF" "$VERIFY_WF"; do
    [[ -f "$workflow" ]] || fail "missing workflow: $workflow"
    require_text "$workflow" "workflow_dispatch:"
    require_text "$workflow" "runs-on: xcode-27"
done

# Build Candidate: one build, publishable candidate, fast/strict.
require_text "$BUILD_WF" "candidate_sha:"
require_text "$BUILD_WF" "release_mode:"
require_text "$BUILD_WF" "fast"
require_text "$BUILD_WF" "strict"
require_text "$BUILD_WF" 'ref: ${{ inputs.candidate_sha }}'
require_text "$BUILD_WF" "CANDIDATE_TYPE: release_candidate"
require_text "$BUILD_WF" 'NOTARIZE: "true"'
require_text "$BUILD_WF" "bash scripts/package-release.sh"
require_text "$BUILD_WF" "name: status-trio-release-package"
require_text "$BUILD_WF" "SPARKLE_PRIVATE_KEY"
require_text "$BUILD_WF" "needs.native.result == 'skipped'"

# Publish Existing Candidate: candidate_run_id only, no build/sign/notarize.
require_text "$PUBLISH_WF" "candidate_run_id:"
require_text "$PUBLISH_WF" "environment:"
require_text "$PUBLISH_WF" "group: status-trio-release-publish"
require_text "$PUBLISH_WF" "bash scripts/validate-candidate-provenance.sh"
require_text "$PUBLISH_WF" "bash scripts/publish-release.sh"
for forbidden in \
    "bash scripts/package-release.sh" \
    "bash scripts/build-app.sh" \
    "swift build" \
    "xcodebuild build" \
    "codesign --sign" \
    "notarytool submit" \
    "create-dmg" \
    "hdiutil create" \
    "SPARKLE_PRIVATE_KEY" \
    "DEVELOPER_ID_CERTIFICATE_P12" \
    "prepare-release-body.sh"; do
    forbid_text "$PUBLISH_WF" "$forbidden"
done

# Verify Candidate: strict evidence only, never rebuild the artifact.
require_text "$VERIFY_WF" "candidate_run_id:"
require_text "$VERIFY_WF" "name: status-trio-strict-evidence"
require_text "$VERIFY_WF" 'verification_level: "strict"'
for forbidden in \
    "bash scripts/package-release.sh" \
    "bash scripts/build-app.sh" \
    "codesign --sign" \
    "notarytool submit" \
    "SPARKLE_PRIVATE_KEY" \
    "DEVELOPER_ID_CERTIFICATE_P12"; do
    forbid_text "$VERIFY_WF" "$forbidden"
done

echo "candidate workflow policy: OK"

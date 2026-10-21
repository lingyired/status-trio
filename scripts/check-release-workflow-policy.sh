#!/usr/bin/env bash
# Fails closed when release-only CI regresses or publication gains build powers.
set -euo pipefail

ROOT="${STATUS_TRIO_RELEASE_POLICY_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
WORKFLOW="$ROOT/.github/workflows/release.yml"
PUBLISH_SCRIPT="$ROOT/scripts/publish-release.sh"

fail() {
    echo "release workflow policy check failed: $*" >&2
    exit 1
}

require_text() {
    local path="$1"
    local text="$2"
    grep -Fq -- "$text" "$path" || fail "$path must contain: $text"
}

forbid_text() {
    local path="$1"
    local text="$2"
    if grep -Fq -- "$text" "$path"; then
        fail "$path must not contain: $text"
    fi
}

[[ -f "$WORKFLOW" ]] || fail "release workflow is missing"
[[ -f "$PUBLISH_SCRIPT" ]] || fail "publish script is missing"

require_text "$WORKFLOW" "workflow_dispatch:"
require_text "$WORKFLOW" "candidate_sha:"
require_text "$WORKFLOW" "^[0-9a-f]{40}$"
require_text "$WORKFLOW" 'refs/heads/main'
require_text "$WORKFLOW" "ref: \${{ inputs.candidate_sha }}"
require_text "$WORKFLOW" "group: status-trio-release-publish"
require_text "$WORKFLOW" "  verify:"
require_text "$WORKFLOW" "  package:"
require_text "$WORKFLOW" "  publish:"
require_text "$WORKFLOW" "needs: verify"
require_text "$WORKFLOW" "needs: [verify, package]"
require_text "$WORKFLOW" "name: status-trio-release-package"
require_text "$WORKFLOW" "bash scripts/package-release.sh"
require_text "$WORKFLOW" "bash scripts/publish-release.sh"
require_text "$WORKFLOW" "RESOLVED_RELEASE_REPO: \${{ vars.RELEASE_REPO || 'lingyired/status-trio' }}"
require_text "$WORKFLOW" "RESOLVED_RELEASE_BRANCH: \${{ vars.RELEASE_BRANCH || 'main' }}"
require_text "$WORKFLOW" "NOTES_MODE=publish"
require_text "$WORKFLOW" "NOTES_MODE=package"
require_text "$WORKFLOW" "RELEASE_REPO: \${{ env.RESOLVED_RELEASE_REPO }}"
require_text "$WORKFLOW" "RELEASE_BRANCH: \${{ env.RESOLVED_RELEASE_BRANCH }}"
require_text "$WORKFLOW" "bash scripts/test.sh"
require_text "$WORKFLOW" "needs.verify.outputs.candidate_sha"
require_text "$WORKFLOW" "needs.verify.outputs.version"
require_text "$WORKFLOW" "needs.verify.outputs.build"
require_text "$WORKFLOW" "needs.verify.outputs.tag"
require_text "$WORKFLOW" "xcode-27"
require_text "$WORKFLOW" "/Applications/Xcode_27.app/Contents/Developer"
require_text "$WORKFLOW" "xcrun --sdk macosx --show-sdk-version"
if [[ "$(grep -c 'runs-on: xcode-27' "$WORKFLOW")" -ne 3 ]]; then
    fail "verify, package, and publish must all run on xcode-27"
fi
if grep -Eq '^    runs-on: (macos-|ubuntu-|windows-)' "$WORKFLOW"; then
    fail "release jobs must not fall back to a generic runner"
fi

for forbidden in \
    "push:" \
    "github.ref_name" \
    "github.event_name == 'push'" \
    "scripts/prepare-release-body.sh" \
    "gh release create --target" \
    "bash scripts/build-app.sh" \
    "hdiutil create" \
    "notarytool submit"; do
    forbid_text "$WORKFLOW" "$forbidden"
done

if ! grep -Eq '^      candidate_sha:$' "$WORKFLOW"; then
    fail "workflow must declare a candidate_sha input"
fi

for forbidden in \
    "swift build" \
    "bash scripts/build-app.sh" \
    "hdiutil create" \
    "notarytool submit" \
    "codesign --force" \
    "SKIP_SOURCE_SHA_CHECK" \
    "TEST_SPARKLE_METADATA"; do
    forbid_text "$PUBLISH_SCRIPT" "$forbidden"
done

for production_script in "$ROOT/scripts/package-release.sh" "$ROOT/scripts/release.sh"; do
    for forbidden in \
        "SKIP_SOURCE_SHA_CHECK" \
        "TEST_SPARKLE_METADATA" \
        "BUILD_APP=" \
        "VERIFY_PLATFORM="; do
        forbid_text "$production_script" "$forbidden"
    done
done

job_block() {
    local name="$1"
    awk -v name="$name" '
        BEGIN { in_job = 0; in_fence = 0 }
        /^  [A-Za-z0-9_-]+:$/ {
            in_job = ($0 == "  " name ":")
        }
        in_job { print }
    ' "$WORKFLOW"
}

VERIFY_BLOCK="$(job_block verify)"
PACKAGE_BLOCK="$(job_block package)"
PUBLISH_BLOCK="$(job_block publish)"

[[ -n "$VERIFY_BLOCK" ]] || fail "verify job is missing"
[[ -n "$PACKAGE_BLOCK" ]] || fail "package job is missing"
[[ -n "$PUBLISH_BLOCK" ]] || fail "publish job is missing"
if printf '%s\n' "$VERIFY_BLOCK" | grep -Eq '^[[:space:]]+swift test([[:space:]]|$)'; then
    fail "verify job must run scripts/test.sh so forbidden-pattern checks cannot be bypassed"
fi
for required_check in \
    "scripts/test-mobile-battery-source-cache.sh" \
    "scripts/test-mobile-battery-clang-version.sh" \
    "scripts/test-verify-local.sh" \
    "scripts/test-verify-local-bundle.sh" \
    "scripts/test-workflow-policy.sh"; do
    printf '%s\n' "$VERIFY_BLOCK" | grep -Fq "bash $required_check" ||
        fail "verify job must run $required_check"
done
printf '%s\n' "$PACKAGE_BLOCK" | grep -Fq '      name: distribution' ||
    fail "package job must use the protected distribution environment"
printf '%s\n' "$PUBLISH_BLOCK" | grep -Fq '      name: distribution' ||
    fail "publish job must use the protected distribution environment"
printf '%s\n' "$VERIFY_BLOCK" | grep -Fq 'bash scripts/test-release-notarization.sh' ||
    fail "verify job must run the offline release notarization regressions"

printf '%s\n' "$VERIFY_BLOCK" | grep -Fxq '    outputs:' ||
    fail "verify job must declare workflow outputs"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 -Fx '    outputs:' |
    grep -Fq 'candidate_sha: ${{ steps.release.outputs.candidate_sha }}' ||
    fail "verify job must expose candidate_sha output"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 '^    outputs:$' |
    grep -Fq 'version: ${{ steps.release.outputs.version }}' ||
    fail "verify job must expose version output"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 '^    outputs:$' |
    grep -Fq 'build: ${{ steps.release.outputs.build }}' ||
    fail "verify job must expose build output"
printf '%s\n' "$VERIFY_BLOCK" | grep -A6 '^    outputs:$' |
    grep -Fq 'tag: ${{ steps.release.outputs.tag }}' ||
    fail "verify job must expose tag output"

if printf '%s\n' "$VERIFY_BLOCK" | grep -Fq 'secrets.'; then
    fail "verify job must not receive secrets"
fi
if sed -n '/^permissions:$/,/^[^ ]/p' "$WORKFLOW" | grep -Fq 'contents: write'; then
    fail "workflow-level permissions must be read-only"
fi
if printf '%s\n' "$PACKAGE_BLOCK" | grep -Fq 'secrets.GITHUB_TOKEN'; then
    fail "package job must not publish with a GitHub write token"
fi
if printf '%s\n' "$PUBLISH_BLOCK" | grep -Eq 'SPARKLE_PRIVATE_KEY|DEVELOPER_ID_CERTIFICATE|APPSTORE_CONNECT'; then
    fail "publish job must not receive build/signing/notarization secrets"
fi
if printf '%s\n' "$PUBLISH_BLOCK" | grep -Eq 'swift build|build-app\.sh|hdiutil create|notarytool submit|codesign'; then
    fail "publish job must not rebuild, repackage, sign, or notarize"
fi
if printf '%s\n' "$PUBLISH_BLOCK" | grep -Eq 'gh release (create|upload|edit)|update-appcast\.rb'; then
    fail "publish job must delegate publication to scripts/publish-release.sh"
fi

echo "release workflow policy check passed"

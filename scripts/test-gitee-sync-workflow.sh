#!/usr/bin/env bash
# Fails closed if the Gitee mirror workflow can build, sign, publish GitHub, or
# silently lose a release-triggered sync.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/gitee-sync.yml"
RELEASE="$ROOT/.github/workflows/release.yml"
fail() { echo "gitee sync workflow policy failed: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "$1 must contain: $2"; }
forbid() { ! grep -Fq -- "$2" "$1" || fail "$1 must not contain: $2"; }
[[ -f "$WORKFLOW" ]] || fail "gitee-sync.yml is missing"
require "$WORKFLOW" "workflow_dispatch:"
require "$WORKFLOW" "runs-on:"
require "$WORKFLOW" "vars.GITEE_SYNC_RUNNER || 'ubuntu-latest'"
require "$WORKFLOW" "tag:"
require "$WORKFLOW" "required: true"
require "$WORKFLOW" "contents: read"
require "$WORKFLOW" "GITEE_TOKEN: \${{ secrets.GITEE_TOKEN }}"
require "$WORKFLOW" "node --test scripts/test-sync-gitee-release.mjs"
require "$WORKFLOW" "concurrency:"
forbid "$WORKFLOW" "macos-latest"
forbid "$WORKFLOW" "xcodebuild"
forbid "$WORKFLOW" "notarytool"
forbid "$WORKFLOW" "SPARKLE_PRIVATE_KEY"
forbid "$WORKFLOW" "contents: write"
forbid "$WORKFLOW" "release.published"
require "$RELEASE" "uses: actions/checkout@v4"
if ! awk '/^  publish:/{inside=1} inside && /^  [a-z].*:/ && !/^  publish:/{exit} inside{print}' "$RELEASE" | grep -Fq -- "actions: write"; then
    fail "publish job must have actions: write to dispatch sync"
fi
require "$RELEASE" "actions/workflows/gitee-sync.yml/dispatches"
require "$RELEASE" "Gitee mirror sync dispatch failed"
echo "gitee sync workflow policy passed"

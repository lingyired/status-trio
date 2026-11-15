#!/usr/bin/env bash
# GitHub CI only validates; local agents own Gitee mirror writes.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/gitee-sync.yml"
RELEASE="$ROOT/.github/workflows/release.yml"
fail() { echo "gitee mirror policy failed: $*" >&2; exit 1; }
require() { grep -Fq -- "$2" "$1" || fail "$1 must contain: $2"; }
forbid() { ! grep -Fq -- "$2" "$1" || fail "$1 must not contain: $2"; }
require "$WORKFLOW" 'workflow_dispatch:'
require "$WORKFLOW" 'runs-on: ubuntu-latest'
require "$WORKFLOW" 'contents: read'
require "$WORKFLOW" 'bash scripts/test-gitee-mirror.sh'
for text in 'GITEE_TOKEN' 'secrets.' 'xcodebuild' 'notarytool' 'contents: write' 'actions: write' 'release.published' 'sync-gitee-release.mjs sync'; do
    forbid "$WORKFLOW" "$text"
done
require "$RELEASE" 'Gitee mirror pending local Agent sync'
require "$RELEASE" 'node scripts/gitee-mirror-agent.mjs sync'
forbid "$RELEASE" 'actions/workflows/gitee-sync.yml/dispatches'
if awk '/^  publish:/{inside=1} inside{print}' "$RELEASE" | grep -Fq 'actions: write'; then
    fail 'publish must not retain mirror workflow dispatch permissions'
fi
echo 'gitee local Agent handoff and offline CI policy passed'
